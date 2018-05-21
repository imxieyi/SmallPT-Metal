//
//  Shaders.metal
//  SmallPT
//
//  Created by 谢宜 on 2018/5/21.
//  Copyright © 2018年 xieyi. All rights reserved.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include "loki_header.metal"
using namespace metal;

constant float WIDTH [[function_constant(0)]];
constant float HEIGHT [[function_constant(1)]];

struct VertexIn {
    packed_float3 position;
    packed_float3 color;
};
struct VertexOut {
    float4 position [[position]];
    float randseed;
    float2 touch;
};

// Do nothing, just pass on variables.
vertex VertexOut vertex_main(device const VertexIn *vertices [[buffer(0)]],
                             device const float *variables [[buffer(1)]],
                             uint vertexId [[vertex_id]]) {
    VertexOut out;
    out.position = float4(vertices[vertexId].position, 1);
    out.randseed = variables[0];
    out.touch.x = variables[1];
    out.touch.y = variables[2];
    return out;
}

/*
 
 This shader is an attempt at porting smallpt to GLSL.
 
 See what it's all about here:
 http://www.kevinbeason.com/smallpt/
 
 The code is based in particular on the slides by David Cline.
 
 Some differences:
 
 - For optimization purposes, the code considers there is
 only one light source (see the commented loop)
 - Russian roulette and tent filter are not implemented
 
 I spent quite some time pulling my hair over inconsistent
 behavior between Chrome and Firefox, Angle and native. I
 expect many GLSL related bugs to be lurking, on top of
 implementation errors. Please Let me know if you find any.
 
 --
 Zavie
 
 */

// Play with the two following values to change quality.
// You want as many samples as your GPU can bear. :)
#define SAMPLES 6
#define MAXDEPTH 4
#define ENABLE_NEXT_EVENT_PREDICTION

// Uncomment to see how many samples never reach a light source
//#define DEBUG

// Not used for now
#define DEPTH_RUSSIAN 2

#define PI 3.14159265359
#define DIFF 0
#define SPEC 1
#define REFR 2
#define NUM_SPHERES 9

struct Ray {
    float3 o, d;
    Ray(float3 o, float3 d) {
        this->o = o;
        this->d = d;
    }
};
struct Sphere {
    float r;
    float3 p, e, c;
    float refl;
};

constant Sphere lightSourceVolume = {20., float3(50., 81.6, 81.6), float3(12.), float3(0.), DIFF};
constant Sphere spheres[NUM_SPHERES] = {
    {1e5, float3(-1e5+1., 40.8, 81.6),    float3(0.), float3(.75, .25, .25), DIFF},
    {1e5, float3( 1e5+99., 40.8, 81.6),float3(0.), float3(.25, .25, .75), DIFF},
    {1e5, float3(50., 40.8, -1e5),        float3(0.), float3(.75), DIFF},
    {1e5, float3(50., 40.8,  1e5+170.),float3(0.), float3(0.), DIFF},
    {1e5, float3(50., -1e5, 81.6),        float3(0.), float3(.75), DIFF},
    {1e5, float3(50.,  1e5+81.6, 81.6),float3(0.), float3(.75), DIFF},
    {16.5, float3(27., 16.5, 47.),     float3(0.), float3(1.), SPEC},
    {16.5, float3(73., 16.5, 78.),     float3(0.), float3(.7, 1., .9), REFR},
    {600., float3(50., 681.33, 81.6),    float3(12.), float3(0.), DIFF}
};

float intersect(Sphere s, Ray r) {
    float3 op = s.p - r.o;
    float t, epsilon = 1e-3, b = dot(op, r.d), det = b * b - dot(op, op) + s.r * s.r;
    if (det < 0.) return 0.; else det = sqrt(det);
    return (t = b - det) > epsilon ? t : ((t = b + det) > epsilon ? t : 0.);
}

struct IntersectResult {
    int id;
    float t;
    Sphere s;
    IntersectResult(int id, float t, Sphere s) {
        this->id = id;
        this->t = t;
        this->s = s;
    }
};

IntersectResult intersect(Ray r, int avoid) {
    int id = -1;
    float t = 1e5;
    Sphere s = spheres[0];
    for (int i = 0; i < NUM_SPHERES; ++i) {
        Sphere S = spheres[i];
        float d = intersect(S, r);
        if (i!=avoid && d!=0. && d<t) { t = d; id = i; s=S; }
    }
    IntersectResult ir(id, t, s);
    return ir;
}

float3 jitter(float3 d, float phi, float sina, float cosa) {
    float3 w = normalize(d), u = normalize(cross(w.yzx, w)), v = cross(w, u);
    return (u*cos(phi) + v*sin(phi)) * sina + w * cosa;
}

float3 radiance(Ray r, Loki loki) {
    float3 acc = float3(0.);
    float3 mask = float3(1.);
    int id = -1;
    for (int depth = 0; depth < MAXDEPTH; ++depth) {
        IntersectResult ir = intersect(r, id);
        float t = ir.t;
        Sphere obj = ir.s;
        if ((id = ir.id) < 0) break;
        float3 x = t * r.d + r.o;
        float3 n = normalize(x - obj.p), nl = n * sign(-dot(n, r.d));
        
        //float3 f = obj.c;
        //float p = dot(f, float3(1.2126, 0.7152, 0.0722));
        //if (depth > DEPTH_RUSSIAN || p == 0.) if (rand() < p) f /= p; else { acc += mask * obj.e * E; break; }
        
        if (obj.refl == DIFF) {
            float r2 = loki.rand();
            float3 d = jitter(nl, 2.*PI*loki.rand(), sqrt(r2), sqrt(1. - r2));
            float3 e = float3(0.);
#ifdef ENABLE_NEXT_EVENT_PREDICTION
            //for (int i = 0; i < NUM_SPHERES; ++i)
            {
                // Sphere s = sphere(i);
                // if (dot(s.e, float3(1.)) == 0.) continue;
                
                // Normally we would loop over the light sources and
                // cast rays toward them, but since there is only one
                // light source, that is mostly occluded, here goes
                // the ad hoc optimization:
                Sphere s = lightSourceVolume;
                int i = 8;
                
                float3 l0 = s.p - x;
                float cos_a_max = sqrt(1. - clamp(s.r * s.r / dot(l0, l0), 0., 1.));
                float cosa = mix(cos_a_max, 1., loki.rand());
                float3 l = jitter(l0, 2.*PI*loki.rand(), sqrt(1. - cosa*cosa), cosa);
                
                IntersectResult ir = intersect(Ray(x, l), id);
                t = ir.t;
                s = ir.s;
                if (ir.id == i) {
                    float omega = 2. * PI * (1. - cos_a_max);
                    e += (s.e * clamp(dot(l, n),0.,1.) * omega) / PI;
                }
            }
#endif
            float E = 1.;//float(depth==0);
            acc += mask * obj.e * E + mask * obj.c * e;
            mask *= obj.c;
            r = Ray(x, d);
        } else if (obj.refl == SPEC) {
            acc += mask * obj.e;
            mask *= obj.c;
            r = Ray(x, reflect(r.d, n));
        } else {
            float a=dot(n,r.d), ddn=abs(a);
            float nc=1., nt=1.5, nnt=mix(nc/nt, nt/nc, float(a>0.));
            float cos2t=1.-nnt*nnt*(1.-ddn*ddn);
            r = Ray(x, reflect(r.d, n));
            if (cos2t>0.) {
                float3 tdir = normalize(r.d*nnt + sign(a)*n*(ddn*nnt+sqrt(cos2t)));
                float R0=(nt-nc)*(nt-nc)/((nt+nc)*(nt+nc)),
                c = 1.-mix(ddn,dot(tdir, n),float(a>0.));
                float Re=R0+(1.-R0)*c*c*c*c*c,P=.25+.5*Re,RP=Re/P,TP=(1.-Re)/(1.-P);
                if (loki.rand()<P) { mask *= RP; }
                else { mask *= obj.c*TP; r = Ray(x, tdir); }
            }
        }
    }
    return acc;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    float2 uv = float2(in.position.x / WIDTH * 2 - 1., 1. - in.position.y / HEIGHT * 2);
    float2 iResolution(WIDTH, HEIGHT);
    if (in.touch.y != 0) in.touch.y = HEIGHT - in.touch.y;
    float3 camPos = float3((2. * ((in.touch.x==0&&in.touch.y==0)?.5*iResolution:in.touch) / iResolution - 1.) * float2(48., 40.) + float2(50., 40.8), 169.);
    float3 cz = normalize(float3(50., 40., 81.6) - camPos);
    float3 cx = float3(1., 0., 0.);
    float3 cy = normalize(cross(cx, cz)); cx = cross(cz, cy);
    float3 color = float3(0.);
    Loki loki(in.position.x, in.position.y, in.randseed);
    for (int i = 0; i < SAMPLES; ++i)
    {
#ifdef DEBUG
        float3 test = radiance(Ray(camPos, normalize(.53135 * (iResolution.x/iResolution.y*uv.x * cx + uv.y * cy) + cz)));
        if (dot(test, test) > 0.) color += float3(1.); else color += float3(0.5,0.,0.1);
#else
        color += radiance(Ray(camPos, normalize(.53135 * (iResolution.x/iResolution.y*uv.x * cx + uv.y * cy) + cz)), loki);
#endif
    }
    return float4(pow(clamp(color/float(SAMPLES), 0., 1.), float3(1./2.2)), 1.);
}

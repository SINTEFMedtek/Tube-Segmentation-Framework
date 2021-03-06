#include "HistogramPyramids.clh"

__constant sampler_t sampler = CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_CLAMP_TO_EDGE | CLK_FILTER_NEAREST;
__constant sampler_t interpolationSampler = CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_CLAMP_TO_EDGE | CLK_FILTER_LINEAR;
__constant sampler_t samplerClamp = CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_CLAMP | CLK_FILTER_NEAREST;

#define LPOS(pos) pos.x+pos.y*get_global_size(0)+pos.z*get_global_size(0)*get_global_size(1)

#ifdef VECTORS_16BIT
#define FLOAT_TO_SNORM16_4(vector) convert_short4_sat_rte(vector * 32767.0f)
#define SNORM16_TO_FLOAT_4(vector) max(-1.0f, convert_float4(vector) / 32767.0f)
#define FLOAT_TO_SNORM16_3(vector) convert_short3_sat_rte(vector * 32767.0f)
#define SNORM16_TO_FLOAT_3(vector) max(-1.0f, convert_float3(vector) / 32767.0f)
#define FLOAT_TO_SNORM16_2(vector) convert_short2_sat_rte(vector * 32767.0f)
#define SNORM16_TO_FLOAT_2(vector) max(-1.0f, convert_float2(vector) / 32767.0f)
#define FLOAT_TO_SNORM16(vector) convert_short_sat_rte(vector * 32767.0f)
#define SNORM16_TO_FLOAT(vector) max(-1.0f, convert_float(vector) / 32767.0f)
#define VECTOR_FIELD_TYPE short
#define UNORM16_TO_FLOAT(v) (float)v / 65535.0f
#define FLOAT_TO_UNORM16(v) convert_ushort_sat_rte(v * 65535.0f)
#define TDF_TYPE ushort
#else
#define FLOAT_TO_SNORM16_4(vector) vector
#define SNORM16_TO_FLOAT_4(vector) vector
#define FLOAT_TO_SNORM16_3(vector) vector
#define SNORM16_TO_FLOAT_3(vector) vector
#define FLOAT_TO_SNORM16_2(vector) vector
#define SNORM16_TO_FLOAT_2(vector) vector
#define FLOAT_TO_SNORM16(vector) vector
#define SNORM16_TO_FLOAT(vector) vector
#define VECTOR_FIELD_TYPE float
#define UNORM16_TO_FLOAT(v) v
#define FLOAT_TO_UNORM16(v) v
#define TDF_TYPE float
#endif

// Intialize 2D image to 0
__kernel void init2DImage(
    __write_only image2d_t image
    ) {
    write_imageui(image, (int2)(get_global_id(0), get_global_id(1)), (uint4)(0,0,0,0));
}

// Intialize int buffer to 0
__kernel void initIntBuffer(
    __global int * buffer
    ) {
    buffer[get_global_id(0)] = 0;
}

// Intialize char buffer to 0
__kernel void initCharBuffer(
    __global char * buffer
    ) {
    buffer[get_global_id(0)] = 0;
}

// Intialize int buffer to its ID
__kernel void initIntBufferID(
    __global int * buffer,
    __private int sum
    ) {
    int id = get_global_id(0); 
    if(id >= sum)
        id = 0;
    buffer[id] = id;
}

// Forward declaration of eigen_decomp function
void eigen_decomposition(float M[3][3], float V[3][3], float e[3]);

float3 gradientNormalized(
        __read_only image3d_t volume,   // Volume to perform gradient on
        int4 pos,                       // Position to perform gradient on
        int volumeComponent,            // The volume component to perform gradient on: 0, 1 or 2
        int dimensions                  // The number of dimensions to perform gradient in: 1, 2 or 3
    ) {
    float f100, f_100, f010, f0_10, f001, f00_1;
    switch(volumeComponent) {
        case 0:
    f100 = read_imagef(volume, sampler, pos + (int4)(1,0,0,0)).x; 
    f_100 = read_imagef(volume, sampler, pos - (int4)(1,0,0,0)).x;
    if(dimensions > 1) {
    f010 = read_imagef(volume, sampler, pos + (int4)(0,1,0,0)).x; 
    f0_10 = read_imagef(volume, sampler, pos - (int4)(0,1,0,0)).x;
    }
    if(dimensions > 2) {
    f001 = read_imagef(volume, sampler, pos + (int4)(0,0,1,0)).x;
    f00_1 = read_imagef(volume, sampler, pos - (int4)(0,0,1,0)).x;
    }
    break;
        case 1:
    f100 = read_imagef(volume, sampler, pos + (int4)(1,0,0,0)).y;
    f_100 = read_imagef(volume, sampler, pos - (int4)(1,0,0,0)).y;
    if(dimensions > 1) {
    f010 = read_imagef(volume, sampler, pos + (int4)(0,1,0,0)).y;
    f0_10 = read_imagef(volume, sampler, pos - (int4)(0,1,0,0)).y;
    }
    if(dimensions > 2) {
    f001 = read_imagef(volume, sampler, pos + (int4)(0,0,1,0)).y;
    f00_1 = read_imagef(volume, sampler, pos - (int4)(0,0,1,0)).y;
    }
    break;
        case 2:
    f100 = read_imagef(volume, sampler, pos + (int4)(1,0,0,0)).z;
    f_100 = read_imagef(volume, sampler, pos - (int4)(1,0,0,0)).z;
    if(dimensions > 1) {
    f010 = read_imagef(volume, sampler, pos + (int4)(0,1,0,0)).z;
    f0_10 = read_imagef(volume, sampler, pos - (int4)(0,1,0,0)).z;
    }
    if(dimensions > 2) {
    f001 = read_imagef(volume, sampler, pos + (int4)(0,0,1,0)).z;
    f00_1 = read_imagef(volume, sampler, pos - (int4)(0,0,1,0)).z;
    }
    break;
    }

    float3 grad = {
        0.5f*(f100/read_imagef(volume, sampler, pos+(int4)(1,0,0,0)).w-f_100/read_imagef(volume, sampler, pos-(int4)(1,0,0,0)).w), 
        0.5f*(f010/read_imagef(volume, sampler, pos+(int4)(0,1,0,0)).w-f0_10/read_imagef(volume, sampler, pos-(int4)(0,1,0,0)).w),
        0.5f*(f001/read_imagef(volume, sampler, pos+(int4)(0,0,1,0)).w-f00_1/read_imagef(volume, sampler, pos-(int4)(0,0,1,0)).w)
    };


    return grad;
}

float3 gradient(
        __read_only image3d_t volume,   // Volume to perform gradient on
        int4 pos,                       // Position to perform gradient on
        int volumeComponent,            // The volume component to perform gradient on: 0, 1 or 2
        int dimensions                  // The number of dimensions to perform gradient in: 1, 2 or 3
    ) {
    float f100, f_100, f010, f0_10, f001, f00_1;
    switch(volumeComponent) {
        case 0:
    f100 = read_imagef(volume, sampler, pos + (int4)(1,0,0,0)).x; 
    f_100 = read_imagef(volume, sampler, pos - (int4)(1,0,0,0)).x;
    if(dimensions > 1) {
    f010 = read_imagef(volume, sampler, pos + (int4)(0,1,0,0)).x; 
    f0_10 = read_imagef(volume, sampler, pos - (int4)(0,1,0,0)).x;
    }
    if(dimensions > 2) {
    f001 = read_imagef(volume, sampler, pos + (int4)(0,0,1,0)).x;
    f00_1 = read_imagef(volume, sampler, pos - (int4)(0,0,1,0)).x;
    }
    break;
        case 1:
    f100 = read_imagef(volume, sampler, pos + (int4)(1,0,0,0)).y;
    f_100 = read_imagef(volume, sampler, pos - (int4)(1,0,0,0)).y;
    if(dimensions > 1) {
    f010 = read_imagef(volume, sampler, pos + (int4)(0,1,0,0)).y;
    f0_10 = read_imagef(volume, sampler, pos - (int4)(0,1,0,0)).y;
    }
    if(dimensions > 2) {
    f001 = read_imagef(volume, sampler, pos + (int4)(0,0,1,0)).y;
    f00_1 = read_imagef(volume, sampler, pos - (int4)(0,0,1,0)).y;
    }
    break;
        case 2:
    f100 = read_imagef(volume, sampler, pos + (int4)(1,0,0,0)).z;
    f_100 = read_imagef(volume, sampler, pos - (int4)(1,0,0,0)).z;
    if(dimensions > 1) {
    f010 = read_imagef(volume, sampler, pos + (int4)(0,1,0,0)).z;
    f0_10 = read_imagef(volume, sampler, pos - (int4)(0,1,0,0)).z;
    }
    if(dimensions > 2) {
    f001 = read_imagef(volume, sampler, pos + (int4)(0,0,1,0)).z;
    f00_1 = read_imagef(volume, sampler, pos - (int4)(0,0,1,0)).z;
    }
    break;
    }

    float3 grad = {
        0.5f*(f100-f_100), 
        0.5f*(f010-f0_10),
        0.5f*(f001-f00_1)
    };


    return grad;
}

__kernel void linkLengths(
        __global int const * restrict positions,
        __write_only image2d_t lengths
        ) {
    const float3 xa = convert_float3(vload3(get_global_id(0), positions));
    const float3 xb = convert_float3(vload3(get_global_id(1), positions));

    write_imagef(lengths, (int2)(get_global_id(0), get_global_id(1)), (float4)(distance(xa,xb),0.0f,0.0f,0.0f));
}

__kernel void compact(
        __read_only image2d_t lengths,
        volatile __global int * incs,
        __write_only image2d_t compacted_lengths,
        __private float maxDistance
        ) {
    const int i = get_global_id(0);
    const int j = get_global_id(1);

    float length = read_imagef(lengths, sampler, (int2)(i,j)).x;
    if(length < maxDistance && length > 0.0f) {
        volatile int nr = atomic_inc(&(incs[i]));
        write_imagef(compacted_lengths, (int2)(i,nr), (float4)(length, j, 0, 0));
    }
}

__kernel void linkCenterpoints(
        __read_only image3d_t TDF,
        __global int const * restrict positions,
        __write_only image2d_t edges,
        __read_only image2d_t compacted_lengths,
        __private int sum,
        __private float minAvgTDF,
        __private float maxDistance
    ) {
    int id = get_global_id(0);
    if(id >= sum)
        id = 0;
    float3 xa = convert_float3(vload3(id, positions));
    //printf("%f %f %f\n",xa.x,xa.y,xa.z);

    int2 bestPair;
    float shortestDistance = maxDistance*2;
    bool validPairFound = false;
    for(int i = 0; i < sum; i++) {
        float2 cl = read_imagef(compacted_lengths, sampler, (int2)(id,i)).xy;

        // reached the end?
        if(cl.x == 0.0f)
            break;

    float3 xb = convert_float3(vload3(cl.y, positions));
    int db = round(cl.x);
    if(db >= shortestDistance)
        continue;
    for(int j = 0; j < i; j++) {
        float2 cl2  = read_imagef(compacted_lengths, sampler, (int2)(id,j)).xy;
        if(cl2.y == cl.y) 
            continue;

        // reached the end?
        if(cl2.x == 0.0f)
            break;
    float3 xc = convert_float3(vload3(cl2.y, positions));

    // Check distance between xa and xb
    int dc = round(cl2.x);

    float minTDF = 0.0f;
    float maxVarTDF = 1.005f;
    float maxIntensity = 1.3f;
    float maxAvgIntensity = 1.2f;
    float maxVarIntensity = 1.005f;

    if(db+dc < shortestDistance) {
        // Check angle
        float3 ab = (xb-xa);
        float3 ac = (xc-xa);
        float angle = acos(dot(normalize(ab), normalize(ac)));
        if(angle < 2.0f) // 120 degrees
            continue;
        // Check TDF
        float avgTDF = 0.0f;
        float avgIntensity = 0.0f;
        for(int k = 0; k <= db; k++) {
            float alpha = (float)k/db;
float3 p = xa+ab*alpha;
            float t = read_imagef(TDF, interpolationSampler, p.xyzz).x; 
            avgTDF += t;
        }
        avgTDF /= db+1;
        if(avgTDF < minAvgTDF)
            continue;

/*
        float varTDF = 0.0f;
        for(int k = 0; k <= db; k++) {
            float alpha = (float)k/db;
float3 p = xa+ab*alpha;
            float t = read_imagef(TDF, interpolationSampler, p.xyzz).x; 
            float i = read_imagef(intensity, interpolationSampler, p.xyzz).x; 
            varIntensity += (i-avgIntensity)*(i-avgIntensity);
            varTDF += (t-avgTDF)*(t-avgTDF);
            if(i > maxIntensity || t < minTDF) {
                invalid = true;
                break;
            }
        }
        if(invalid)
            continue;

        if(db > 4 && varTDF / (db+1) > maxVarTDF)
            continue;
            */

        avgTDF = 0.0f;
        for(int k = 0; k <= dc; k++) {
            float alpha = (float)k/dc;
            float3 p = xa+ac*alpha;
            float t = read_imagef(TDF, interpolationSampler, p.xyzz).x; 
            avgTDF += t;
        }
        avgTDF /= dc+1;

        if(avgTDF < minAvgTDF)
            continue;

    /*
        for(int k = 0; k <= dc; k++) {
            float alpha = (float)k/dc;
float3 p = xa+ac*alpha;
            float t = read_imagef(TDF, interpolationSampler, p.xyzz).x; 
            varTDF += (t-avgTDF)*(t-avgTDF);
        }

        if(dc > 4 && varIntensity / (dc+1) > maxVarIntensity)
            continue;
        if(dc > 4 && varTDF / (dc+1) > maxVarTDF)
            continue;
            */

        validPairFound = true;
        bestPair.x = cl.y;
        bestPair.y = cl2.y;
        shortestDistance = db+dc;
    }
    }}

    if(validPairFound) {
        // Store edges
        int2 edge = {id, bestPair.x};
        int2 edge2 = {id, bestPair.y};
        write_imageui(edges, edge, (uint4)(1,0,0,0));
        write_imageui(edges, edge2, (uint4)(1,0,0,0));
    }
}

__kernel void graphComponentLabeling(
        __global int const * restrict edges,
        volatile __global int * C,
        __global int * m,
        __private int sum
        ) {
    int id = get_global_id(0);
    if(id >= sum)
        id = 0;
    int2 edge = vload2(id, edges);
    const int ca = C[edge.x];
    const int cb = C[edge.y];

    // Find the smallest C value and store in C in the others
    if(ca == cb) {
        return;
    } else {
        if(ca < cb) {
            // ca is smallest
            atomic_min(&C[edge.y], ca);
        } else {
            // cb is smallest
            atomic_min(&C[edge.x], cb);
        }
        m[0] = 1; // register change
    }
}

__kernel void calculateTreeLength(
        __global int const * restrict C,
        volatile __global int * S
    ) {
    const int id = get_global_id(0);
    atomic_inc(&S[C[id]]);
}

__kernel void removeSmallTrees(
        __global int const * restrict edges,
        __global int const * restrict vertices,
        __global int const * restrict C,
        __global int const * restrict S,
        __private int minTreeLength,
        __global char * centerlines,
        __private int width,
        __private int height
    ) {
   // Find the edges that are part of the large trees 
    const int id = get_global_id(0);
    int2 edge = vload2(id, edges);
    const int ca = C[edge.x];
    if(S[ca] >= minTreeLength) {
        const float3 xa = convert_float3(vload3(edge.x, vertices));
        const float3 xb = convert_float3(vload3(edge.y, vertices));
        int l = round(length(xb-xa));
        for(int i = 0; i < l; i++) {
            const float alpha = (float)i/l;
            //write_imagei(centerlines, convert_int3(round(xa+(xb-xa)*alpha)).xyzz, 1);
            const int3 pos = convert_int3(round(xa+(xb-xa)*alpha));
            centerlines[pos.x+pos.y*width+pos.z*width*height] = 1;
        }
    }
}

__kernel void removeDuplicateEdges(
		__read_only image2d_t edgeTuples,
		__write_only image2d_t edgeTuples2
	) {
	const int2 pos = {get_global_id(0), get_global_id(1)};
	if(read_imageui(edgeTuples, sampler, pos).x == 0) {
		write_imageui(edgeTuples2,pos, (uint4)(0,0,0,0));
	} else if(pos.x > pos.y) {
		// Check if opposite is an edge
		if(read_imageui(edgeTuples, sampler, (int2)(pos.y,pos.x)).x == 1) {
			// opposite exists => remove this one
			write_imageui(edgeTuples2,pos, (uint4)(0,0,0,0));
		} else {
			// opposite doesn't exist => save this one
			write_imageui(edgeTuples2,pos, (uint4)(1,0,0,0));
		}
	} else {
		write_imageui(edgeTuples2,pos, (uint4)(1,0,0,0));
	}
}

#define SQR_MAG(pos) read_imagef(vectorField, sampler, pos).w

__kernel void dd(
    __read_only image3d_t TDF,
    __read_only image3d_t centerpointCandidates,
    __global uchar * centerpoints,
    __private int cubeSize
    ) {

    int4 bestPos;
    float bestTDF = 0.0f;
    int4 readPos = {
        get_global_id(0)*cubeSize,
        get_global_id(1)*cubeSize,
        get_global_id(2)*cubeSize,
        0
    };
    bool found = false;
    for(int a = 0; a < cubeSize; a++) {
    for(int b = 0; b < cubeSize; b++) {
    for(int c = 0; c < cubeSize; c++) {
        int4 pos = readPos + (int4)(a,b,c,0);
        if(read_imagei(centerpointCandidates, sampler, pos).x == 1) {
            float tdf = read_imagef(TDF, sampler, pos).x;
            if(tdf > bestTDF) {
                found = true;
                bestTDF = tdf;
                bestPos = pos;
            }
        }
    }}}
    if(found) {
        centerpoints[bestPos.x+bestPos.y*get_image_width(TDF)+bestPos.z*get_image_width(TDF)*get_image_height(TDF)] = 1;
    }
}



__kernel void findCandidateCenterpoints(
    __read_only image3d_t TDF,
    __global uchar * centerpoints,
    __private float TDFlimit
    ) {
    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    if(read_imagef(TDF, sampler, pos).x < TDFlimit) {
        centerpoints[LPOS(pos)] = 0;
    } else {
        centerpoints[LPOS(pos)] = 1;
    }
}

__kernel void findCandidateCenterpoints2(
    __read_only image3d_t TDF,
    __read_only image3d_t radius,
    __read_only image3d_t vectorField,
    __global char * centerpoints,
    __private int HP_SIZE,
    __private int sum,
    __global uchar * hp0, // Largest HP
    __global uchar * hp1,
    __global ushort * hp2,
    __global ushort * hp3,
    __global ushort * hp4,
    __global int * hp5,
    __global int * hp6,
    __global int * hp7,
    __global int * hp8,
    __global int * hp9
    ) {
    int target = get_global_id(0);
    if(target >= sum)
        target = 0;
    uint3 size = {get_image_width(TDF),get_image_height(TDF),get_image_depth(TDF)};
    int4 pos = traverseHP3DBuffer(size,target,HP_SIZE,hp0,hp1,hp2,hp3,hp4,hp5,hp6,hp7,hp8,hp9);

    const float thetaLimit = 0.5f;
    const float radii = read_imagef(radius, sampler, pos).x;
    const int maxD = max(min(round(radii), 5.0f), 1.0f);
    bool invalid = false;

    // Find Hessian Matrix
    float3 Fx, Fy, Fz;
    Fx = gradientNormalized(vectorField, pos, 0, 1);
    Fy = gradientNormalized(vectorField, pos, 1, 2);
    Fz = gradientNormalized(vectorField, pos, 2, 3);

    float Hessian[3][3] = {
        {Fx.x, Fy.x, Fz.x},
        {Fy.x, Fy.y, Fz.y},
        {Fz.x, Fz.y, Fz.z}
    };
    
    // Eigen decomposition
    float eigenValues[3];
    float eigenVectors[3][3];
    eigen_decomposition(Hessian, eigenVectors, eigenValues);
    const float3 e1 = {eigenVectors[0][0], eigenVectors[1][0], eigenVectors[2][0]};

    for(int a = -maxD; a <= maxD; a++) {
    for(int b = -maxD; b <= maxD; b++) {
    for(int c = -maxD; c <= maxD; c++) {
        if(a == 0 && b == 0 && c == 0)
            continue;
        const int4 n = pos + (int4)(a,b,c,0);
        const float3 r = {a,b,c};
        const float dp = dot(e1,r);
        const float3 r_projected = r-e1*dp;
        const float theta = acos(dot(normalize(r), normalize(r_projected)));
        if(theta < thetaLimit && length(r) < maxD) {
            if(SQR_MAG(n) < SQR_MAG(pos)) {
                invalid = true;
            }    
        }
    }}}

	centerpoints[pos.x+pos.y*get_image_width(TDF)+pos.z*get_image_width(TDF)*get_image_height(TDF)] = invalid ? 0:1;
}


__kernel void combine(
    __global TDF_TYPE * TDFsmall,
    __global float * radiusSmall,
    __global TDF_TYPE * TDFlarge,
    __global float * radiusLarge
    ) {
    int i = get_global_id(0);
    if(TDFlarge[i] < TDFsmall[i]) {
        TDFlarge[i] = TDFsmall[i];
        radiusLarge[i] = radiusSmall[i];
    }
}

__kernel void initGrowing(
	__read_only image3d_t centerline,
	__global char * initSegmentation,
	__read_only image3d_t avgRadius
	) {
    int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    if(read_imagei(centerline, sampler, pos).x == 1) {
	
    	float radius = read_imagef(avgRadius, sampler, pos).x;
    	int N = min(max(1, (int)round(radius/2.0f)), 4);

        for(int a = -N; a < N+1; a++) {
        for(int b = -N; b < N+1; b++) {
        for(int c = -N; c < N+1; c++) {
            int4 n;
            n.x = pos.x + a;
            n.y = pos.y + b;
            n.z = pos.z + c;
	    if(read_imagei(centerline, sampler, n).x == 0 &&
            n.x >= 0 && n.y >= 0 && n.z >= 0 &&
            n.x < get_global_size(0) && n.y < get_global_size(1) && n.z < get_global_size(2))
            initSegmentation[LPOS(n)] = 2; 
        }}}
	}
}



__kernel void grow(
	__read_only image3d_t currentSegmentation,
	__read_only image3d_t gvf,
	__global char * nextSegmentation,
	__global int * stop
	) {

    int4 X = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    char value = read_imagei(currentSegmentation, sampler, X).x;
    // value of 2, means to check it, 1 means it is already accepted
    if(value == 1) {
        nextSegmentation[LPOS(X)] = 1;
    }else if(value == 2){
	float FNXw = read_imagef(gvf, sampler, X).w;

	bool continueGrowing = false;
	for(int a = -1; a < 2; a++) {
	for(int b = -1; b < 2; b++) {
	for(int c = -1; c < 2; c++) {
	    if(a == 0 && b == 0 && c == 0)
		continue;

	    int4 Y;
	    Y.x = X.x + a;
	    Y.y = X.y + b;
	    Y.z = X.z + c;
	    
	    char valueY = read_imagei(currentSegmentation, sampler, Y).x;
	    if(valueY != 1) {
		float4 FNY = read_imagef(gvf, sampler, Y);
		FNY.x /= FNY.w;
		FNY.y /= FNY.w;
		FNY.z /= FNY.w;
	    if(FNY.w > FNXw /*|| FNXw < 0.1f*/) {

		int4 Z;
		float maxDotProduct = -2.0f;
		for(int a2 = -1; a2 < 2; a2++) {
		for(int b2 = -1; b2 < 2; b2++) {
		for(int c2 = -1; c2 < 2; c2++) {
		    if(a2 == 0 && b2 == 0 && c2 == 0)
			continue;
		    int4 Zc;
		    Zc.x = Y.x+a2;
		    Zc.y = Y.y+b2;
		    Zc.z = Y.z+c2;
		    float3 YZ;
		    YZ.x = Zc.x-Y.x;
		    YZ.y = Zc.y-Y.y;
		    YZ.z = Zc.z-Y.z;
		    YZ = normalize(YZ);
const float v = FNY.x*YZ.x+FNY.y*YZ.y+FNY.z*YZ.z;
		    if(v > maxDotProduct) {
			maxDotProduct = v;
			Z = Zc;
		    }
		}}}

		if(Z.x == X.x && Z.y == X.y && Z.z == X.z) {
            nextSegmentation[LPOS(X)] = 1;
            // Check if in bounds
            if(Y.x >= 0 && Y.y >= 0 && Y.z >= 0 && 
                Y.x < get_global_size(0) && Y.y < get_global_size(1) && Y.z < get_global_size(2)) {
                nextSegmentation[LPOS(Y)] = 2; 
                continueGrowing = true;
            }
		}
	    }}

	}}}

	if(continueGrowing) {
		// Added new items to list (values of 2)
		stop[0] = 0;
	} else {
		// X was not accepted
        nextSegmentation[LPOS(X)] = 0;
	}
}
}

__kernel void sphereSegmentation(
		__read_only image3d_t centerlines,
		__read_only image3d_t radius,
		__global char * segmentation
		) {

    int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};

    if(read_imagei(centerlines,sampler,pos).x == 0)
    	return;

    float r = read_imagef(radius, sampler ,pos).x;
    int N = ceil(r);
    for(int x = -N; x <= N; x++) {
    for(int y = -N; y <= N; y++) {
    for(int z = -N; z <= N; z++) {
    	// calculate distance
    	if(length((float3)(x,y,z)) < r) {
			int4 posN = pos + (int4)(x,y,z,0);
			if(posN.x >= 0 && posN.y >= 0 && posN.z >= 0 &&
                posN.x < get_global_size(0) && posN.y < get_global_size(1) && posN.z < get_global_size(2)) {
                segmentation[posN.x+posN.y*get_global_size(0)+posN.z*get_global_size(0)*get_global_size(1)] = 1;
			}
    	}
    }}}
}

__kernel void cropDatasetThreshold(
        __read_only image3d_t volume,
        __global short * scanLinesInside,
        __private int sliceDirection,
        __private float threshold,
        __private int type
    ) {
	int sliceNr = get_global_id(0);
    short scanLines = 0;
    int scanLineSize, scanLineElementSize;

    if(sliceDirection == 0) {
        scanLineSize = get_image_height(volume);
        scanLineElementSize = get_image_depth(volume);
    } else if(sliceDirection == 1) {
        scanLineSize = get_image_width(volume);
        scanLineElementSize = get_image_depth(volume);
    } else {
        scanLineSize = get_image_height(volume);
        scanLineElementSize = get_image_width(volume);
    }

    for(int scanLine = 0; scanLine < scanLineSize; scanLine++) {

    	bool found = false;
        for(int scanLineElement = 0; scanLineElement < scanLineElementSize; scanLineElement ++) {
			int4 pos;
            if(sliceDirection == 0) {
                pos.x = sliceNr;
                pos.y = scanLine;
                pos.z = scanLineElement;
            } else if(sliceDirection == 1) {
                pos.x = scanLine;
                pos.y = sliceNr;
                pos.z = scanLineElement;
            } else {
                pos.x = scanLineElement;
                pos.y = scanLine;
                pos.z = sliceNr;
            }

            if(type == 1) {
				if(read_imagei(volume,sampler,pos).x > threshold)
					found = true;
            } else if(type == 2) {
				if(read_imageui(volume,sampler,pos).x > threshold)
					found = true;
            } else {
				if(read_imagef(volume,sampler,pos).x > threshold)
					found = true;
            }
        } // End scan line
        if(found)
        	scanLines++;
    }
    scanLinesInside[sliceNr] = scanLines;
}

__kernel void cropDatasetLung(
        __read_only image3d_t volume,
        __global short * scanLinesInside,
        __private int sliceDirection,
        __private int type
    ) {
    short HUlimit = -150;
    if(type == 2)
    	HUlimit += 1024;
    int Wlimit = 30;
    int Blimit = 30;
    int sliceNr = get_global_id(0);
    short scanLines = 0;   
    int scanLineSize, scanLineElementSize;

    if(sliceDirection == 0) {
        scanLineSize = get_image_height(volume);
        scanLineElementSize = get_image_depth(volume);
    } else if(sliceDirection == 1) {
        scanLineSize = get_image_width(volume);
        scanLineElementSize = get_image_depth(volume);
    } else {
        scanLineSize = get_image_height(volume);
        scanLineElementSize = get_image_width(volume);
    }

    for(int scanLine = 0; scanLine < scanLineSize; scanLine++) {
        int currentWcount = 0,
            currentBcount = 0,
            detectedBlackAreas = 0,
            detectedWhiteAreas = 0;
          
        for(int scanLineElement = 0; scanLineElement < scanLineElementSize; scanLineElement ++) {
            int4 pos;
            if(sliceDirection == 0) {
                pos.x = sliceNr;
                pos.y = scanLine;
                pos.z = scanLineElement;
            } else if(sliceDirection == 1) {
                pos.x = scanLine;
                pos.y = sliceNr;
                pos.z = scanLineElement;
            } else {
                pos.x = scanLineElement;
                pos.y = scanLine;
                pos.z = sliceNr;
            }

            short HU;
            if(type == 1) {
				HU = read_imagei(volume, sampler, pos).x;
            }else{
				HU = read_imageui(volume, sampler, pos).x;
            }
            if(HU > HUlimit) {
                if(currentWcount == Wlimit) {
                    detectedWhiteAreas++;
                    currentBcount = 0;
                }
                currentWcount++;
            } else {
                if(currentBcount == Blimit) {
                    detectedBlackAreas++;
                    currentWcount = 0;
                }
                currentBcount++;
            }
        }
        if((detectedWhiteAreas == 2 && detectedBlackAreas == 1) || 
            (detectedBlackAreas > 1 && detectedWhiteAreas > 1)) {
            scanLines++;
        } // End scan line
    }
    scanLinesInside[sliceNr] = scanLines;
} 

__kernel void dilate(
        __read_only image3d_t volume, 
        __global char * result
        ) {
    int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};

    if(read_imagei(volume, sampler, pos).x == 1) {
    for(int a = -1; a < 2 ; a++) { 
        for(int b = -1; b < 2 ; b++) { 
            for(int c = -1; c < 2 ; c++) { 
                int4 nPos = pos + (int4)(a,b,c,0);
                // Check if in bounds
                if(nPos.x >= 0 && nPos.y >= 0 && nPos.z >= 0 &&
                    nPos.x < get_global_size(0) && nPos.y < get_global_size(1) && nPos.z < get_global_size(2))
                result[LPOS(nPos)] = 1;
            }
        }
    }
    }
}

__kernel void erode(
        __read_only image3d_t volume, 
        __global char * result
        ) {
    int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};

    int value = read_imagei(volume, sampler, pos).x;
    if(value == 1) {

    bool keep = true;
    for(int a = -1; a < 2 ; a++) { 
        for(int b = -1; b < 2 ; b++) { 
            for(int c = -1; c < 2 ; c++) { 
                keep = (read_imagei(volume, sampler, pos + (int4)(a,b,c,0)).x == 1 && keep);
            }
        }
    }
        result[LPOS(pos)] = keep ? 1 : 0;
    } else {
        result[LPOS(pos)] = 0;
    }
}

__kernel void toFloat(
        __read_only image3d_t volume,
        __global float * processedVolume,
        __private float minimum,
        __private float maximum,
        __private int type
        ) {
    int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    
    float v;
    if(type == 1) {
        v = read_imagei(volume, sampler, pos).x;
    } else if(type == 2) {
        v = read_imageui(volume, sampler, pos).x;
    } else {
        v = read_imagef(volume, sampler, pos).x;
    }
    v = v > maximum ? maximum : v;
    v = v < minimum ? minimum : v;

    // Convert to floating point representation 0 to 1
    float value = (float)(v - minimum) / (float)(maximum - minimum);
    //printf("%f \n", value);

    // Store value
    processedVolume[LPOS(pos)] = value;
}

__kernel void blurVolumeWithGaussian(
        __read_only image3d_t volume,
        __global float * blurredVolume,
        __private int maskSize,
        __constant float * mask
    ) {

    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    // TODO: need to take into account spacing here?
    
    // Collect neighbor values and multiply with gaussian
    float sum = 0.0f;
    // Calculate the mask size based on sigma (larger sigma, larger mask)
    for(int a = -maskSize; a < maskSize+1; a++) {
        for(int b = -maskSize; b < maskSize+1; b++) {
            for(int c = -maskSize; c < maskSize+1; c++) {
                sum += mask[a+maskSize+(b+maskSize)*(maskSize*2+1)+(c+maskSize)*(maskSize*2+1)*(maskSize*2+1)]
                        *read_imagef(volume, sampler, pos + (int4)(a,b,c,0)).x; 
            }
        }
    }

    blurredVolume[LPOS(pos)] = sum;
}

#define SELECT_BUFFER(vec1,vec2,z,maxZ) z < maxZ ? vec1:vec2
#define SELECT_POS(pos,maxZ) pos.z < maxZ ?  pos.x+pos.y*get_global_size(0)+pos.z*get_global_size(0)*get_global_size(1) : pos.x + pos.y*get_global_size(0) + (pos.z-maxZ)*get_global_size(0)*get_global_size(1)

__kernel void createVectorField(
        __read_only image3d_t volume, 
        __global VECTOR_FIELD_TYPE * vectorField,
        __global VECTOR_FIELD_TYPE * vectorField2,
        __private float Fmax,
        __private int vectorSign,
        __private int maxZ
        ) {
    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};

    // Gradient of volume
    float4 F; 
    F.xyz = gradient(volume, pos, 0, 3); // The sign here is important
    F.w = 0.0f;

F.x = vectorSign*F.x;
F.y = vectorSign*F.y;
F.z = vectorSign*F.z;

    // Fmax normalization
    const float l = length(F);
    F = l < Fmax ? F/(Fmax) : F / (l);
    F.w = 1.0f;

    // Store vector field

    vstore4(FLOAT_TO_SNORM16_4(F), SELECT_POS(pos,maxZ), SELECT_BUFFER(vectorField,vectorField2,pos.z,maxZ));
}


__constant float cosValues[32] = {1.0f, 0.540302f, -0.416147f, -0.989992f, -0.653644f, 0.283662f, 0.96017f, 0.753902f, -0.1455f, -0.91113f, -0.839072f, 0.0044257f, 0.843854f, 0.907447f, 0.136737f, -0.759688f, -0.957659f, -0.275163f, 0.660317f, 0.988705f, 0.408082f, -0.547729f, -0.999961f, -0.532833f, 0.424179f, 0.991203f, 0.646919f, -0.292139f, -0.962606f, -0.748058f, 0.154251f, 0.914742f};
__constant float sinValues[32] = {0.0f, 0.841471f, 0.909297f, 0.14112f, -0.756802f, -0.958924f, -0.279415f, 0.656987f, 0.989358f, 0.412118f, -0.544021f, -0.99999f, -0.536573f, 0.420167f, 0.990607f, 0.650288f, -0.287903f, -0.961397f, -0.750987f, 0.149877f, 0.912945f, 0.836656f, -0.00885131f, -0.84622f, -0.905578f, -0.132352f, 0.762558f, 0.956376f, 0.270906f, -0.663634f, -0.988032f, -0.404038f};

__kernel void circleFittingTDF(
        __read_only image3d_t vectorField,
        __global TDF_TYPE * T,
        __global float * Radius,
        __private float rMin,
        __private float rMax,
        __private float rStep
    ) {
    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};

    // Find Hessian Matrix
    float3 Fx, Fy, Fz;
    if(rMax < 4) {
	    Fx = gradient(vectorField, pos, 0, 1);
	    Fy = gradient(vectorField, pos, 1, 2);
	    Fz = gradient(vectorField, pos, 2, 3);
    } else {
	    Fx = gradientNormalized(vectorField, pos, 0, 1);
	    Fy = gradientNormalized(vectorField, pos, 1, 2);
	    Fz = gradientNormalized(vectorField, pos, 2, 3);
    }


    float Hessian[3][3] = {
        {Fx.x, Fy.x, Fz.x},
        {Fy.x, Fy.y, Fz.y},
        {Fz.x, Fz.y, Fz.z}
    };
    
    // Eigen decomposition
    float eigenValues[3];
    float eigenVectors[3][3];
    eigen_decomposition(Hessian, eigenVectors, eigenValues);
    //const float3 lambda = {eigenValues[0], eigenValues[1], eigenValues[2]};
    //const float3 e1 = {eigenVectors[0][0], eigenVectors[1][0], eigenVectors[2][0]};
    const float3 e2 = {eigenVectors[0][1], eigenVectors[1][1], eigenVectors[2][1]};
    const float3 e3 = {eigenVectors[0][2], eigenVectors[1][2], eigenVectors[2][2]};

    // Circle Fitting
    float maxSum = 0.0f;
    float maxRadius = 0.0f;
    const float4 floatPos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
        int samples = 32;
        int stride = 1;
    for(float radius = rMin; radius <= rMax; radius += rStep) {
        bool negatives = false;
        float radiusSum = 0.0f;
            for(int j = 0; j < samples && !negatives; j++) {
            float3 V_alpha = cosValues[j*stride]*e3 + sinValues[j*stride]*e2;
            float4 position = floatPos + radius*V_alpha.xyzz;
            float3 V = -read_imagef(vectorField, interpolationSampler, position).xyz;
            radiusSum += dot(V, V_alpha);
            //if(dot(normalize(V), normalize(V_alpha)) < 0.2f)
            //    negatives = true;
        }
        //if(negatives) // these instructions may lead to wierd results
        //	continue;
        radiusSum /= samples;
        if(radiusSum > maxSum) {
            maxSum = radiusSum;
            maxRadius = radius;
        } else {
            break;
        }
    }

    // Store result
    T[LPOS(pos)] = FLOAT_TO_UNORM16(maxSum);
    Radius[LPOS(pos)] = maxRadius;
}

__kernel void splineTDF(
        __read_only image3d_t vectorField,
        __global TDF_TYPE * T,
        __private float rMin,
        __private float rMax,
        __private float rStep,
        //__global float * blendingFunctions,
        __private const int arms,
        //__private const int samples,
        __global float * R,
        __private const float minAverageMag
    ) {
    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    int invalid = 0;

    // Find Hessian Matrix
    const float3 Fx = gradientNormalized(vectorField, pos, 0, 1);
    const float3 Fy = gradientNormalized(vectorField, pos, 1, 2);
    const float3 Fz = gradientNormalized(vectorField, pos, 2, 3);

    float Hessian[3][3] = {
        {Fx.x, Fy.x, Fz.x},
        {Fy.x, Fy.y, Fz.y},
        {Fz.x, Fz.y, Fz.z}
    };

    // Eigen decomposition
    float eigenValues[3];
    float eigenVectors[3][3];
    eigen_decomposition(Hessian, eigenVectors, eigenValues);
    const float3 e1 = {eigenVectors[0][0], eigenVectors[1][0], eigenVectors[2][0]};
    const float3 e2 = {eigenVectors[0][1], eigenVectors[1][1], eigenVectors[2][1]};
    const float3 e3 = {eigenVectors[0][2], eigenVectors[1][2], eigenVectors[2][2]};

    float currentVoxelMagnitude = length(read_imagef(vectorField, sampler, pos).xyz);

    float maxRadius[12]; // 12 is maximum nr of arms atm.
    //float minAverageMag = 0.01f; // 0.01
    float avgRadius = 0.0f;
    float sum = 0.0f;
    for(int j = 0; j < arms; j++) {
        maxRadius[j] = 999;
        float alpha = 2 * M_PI_F * j / arms;
        float4 V_alpha = cos(alpha)*e3.xyzz + sin(alpha)*e2.xyzz;
        float prevMagnitude2 = currentVoxelMagnitude;
        float4 position = convert_float4(pos) + rMin*V_alpha;
        float prevMagnitude = length(read_imagef(vectorField, interpolationSampler, position).xyz);
        int up = prevMagnitude2 > prevMagnitude ? 0 : 1;

        // Perform the actual line search
        for(float radius = rMin+rStep; radius <= rMax; radius += rStep) {
            position = convert_float4(pos) + radius*V_alpha;
            float4 vec = read_imagef(vectorField, interpolationSampler, position);
            vec.w = 0.0f;
            float magnitude = length(vec.xyz);

            // Is a border point found?
            if(up == 1 && magnitude < prevMagnitude && (prevMagnitude+magnitude)/2.0f - currentVoxelMagnitude > minAverageMag) { // Dot produt here is test
                maxRadius[j] = radius;
                avgRadius += radius;
                if(dot(normalize(vec.xyz), -normalize(V_alpha.xyz)) < 0.0f) {
                    invalid = 1;
                    sum = 0.0f;
                }
                sum += 1.0f-fabs(dot(normalize(vec.xyz), e1));
                break;
            } // End found border point

            if(magnitude > prevMagnitude) {
                up = 1;
            }
            prevMagnitude = magnitude;
        } // End for each radius

        if(maxRadius[j] == 999 || invalid == 1) {
            invalid = 1;
            break;
        }
    } // End for arms

    avgRadius = avgRadius / arms;
    R[LPOS(pos)] = avgRadius;
    if(invalid != 1) {
        float avgSymmetry = 0.0f;
        for(int j = 0; j < arms/2; j++) {
           avgSymmetry += min(maxRadius[j], maxRadius[arms/2 + j]) /
                max(maxRadius[j], maxRadius[arms/2+j]);
        }
        avgSymmetry /= arms/2;
        T[LPOS(pos)] = FLOAT_TO_UNORM16(min(1.0f, (sum / (arms))*avgSymmetry+0.2f));
    } else {
        T[LPOS(pos)] = 0;
    }
}

__kernel void GVF3DIteration_one_component(
		__global VECTOR_FIELD_TYPE * init_vector_field,
		__global VECTOR_FIELD_TYPE const * restrict read_vector_field,
		__global VECTOR_FIELD_TYPE * write_vector_field,
		__private float mu
	) {
    int4 writePos = {
        get_global_id(0),
        get_global_id(1),
        get_global_id(2),
        0
    };
    // Enforce mirror boundary conditions
    int4 size = {get_global_size(0), get_global_size(1), get_global_size(2), 0};
    int4 pos = writePos;
    pos = select(pos, (int4)(2,2,2,0), pos == (int4)(0,0,0,0));
    pos = select(pos, size-3, pos >= size-1);
    int offset = pos.x+pos.y*size.x+pos.z*size.x*size.y;

    float2 init_vector = SNORM16_TO_FLOAT_2(vload2(offset, init_vector_field));
    float v = SNORM16_TO_FLOAT(read_vector_field[offset]);
    float fx1 = SNORM16_TO_FLOAT(read_vector_field[offset+1]);
    float fx_1 = SNORM16_TO_FLOAT(read_vector_field[offset-1]);
    float fy1 = SNORM16_TO_FLOAT(read_vector_field[offset+size.x]);
    float fy_1 = SNORM16_TO_FLOAT(read_vector_field[offset-size.x]);
    float fz1 = SNORM16_TO_FLOAT(read_vector_field[offset+size.x*size.y]);
    float fz_1 = SNORM16_TO_FLOAT(read_vector_field[offset-size.x*size.y]);

    // Update the vector field: Calculate Laplacian using a 3D central difference scheme
    float laplacian = -6*v + fx1 + fx_1 + fy1 + fy_1 + fz1 + fz_1;

    v += mu * laplacian - (v - init_vector.x)*init_vector.y;

    write_vector_field[writePos.x+writePos.y*size.x+writePos.z*size.x*size.y] = FLOAT_TO_SNORM16(v);
}

__kernel void GVF3DInit_one_component(
		__read_only image3d_t initVectorField,
		__global VECTOR_FIELD_TYPE * vectorField,
		__global VECTOR_FIELD_TYPE * newInitVectorField,
		__private int component // 1 == x, 2 == y, 3 == z
	) {
    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    float4 value = read_imagef(initVectorField, sampler, pos);
    float sqrMag = value.x*value.x+value.y*value.y+value.z*value.z;
    float componentValue;
    if(component == 1) {
    	componentValue = value.x;
    } else if(component == 2) {
    	componentValue = value.y;
    } else {
    	componentValue = value.z;
    }
    int offset = pos.x+pos.y*get_global_size(0)+pos.z*get_global_size(0)*get_global_size(1);
    vectorField[offset] = FLOAT_TO_SNORM16(componentValue);
    vstore2(FLOAT_TO_SNORM16_2((float2)(componentValue, sqrMag)), offset, newInitVectorField);
}

__kernel void GVF3DFinish_one_component(
		__global VECTOR_FIELD_TYPE const * restrict vectorFieldX,
		__global VECTOR_FIELD_TYPE const * restrict vectorFieldY,
		__global VECTOR_FIELD_TYPE const * restrict vectorFieldZ,
		__global VECTOR_FIELD_TYPE * vectorField,
		__global VECTOR_FIELD_TYPE * vectorField2,
		__private int maxZ
	) {
    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    int offset = pos.x+pos.y*get_global_size(0)+pos.z*get_global_size(0)*get_global_size(1);
    float4 v;
    v.x = SNORM16_TO_FLOAT(vectorFieldX[offset]);
    v.y = SNORM16_TO_FLOAT(vectorFieldY[offset]);
    v.z = SNORM16_TO_FLOAT(vectorFieldZ[offset]);
    v.w = 0;
    v.w = length(v) > 0.0f ? length(v) : 1.0f;
    vstore4(FLOAT_TO_SNORM16_4(v), SELECT_POS(pos,maxZ), SELECT_BUFFER(vectorField,vectorField2,pos.z,maxZ));
}

__kernel void GVF3DIteration(
		__read_only image3d_t init_vector_field,
		__global VECTOR_FIELD_TYPE const * restrict read_vector_field,
		__global VECTOR_FIELD_TYPE * write_vector_field,
		__private float mu
		) {
    int4 writePos = {
        get_global_id(0),
        get_global_id(1),
        get_global_id(2),
        0
    };
    // Enforce mirror boundary conditions
    int4 size = {get_global_size(0), get_global_size(1), get_global_size(2), 0};
    int4 pos = writePos;
    pos = select(pos, (int4)(2,2,2,0), pos == (int4)(0,0,0,0));
    pos = select(pos, size-3, pos >= size-1);
    int offset = pos.x+pos.y*size.x+pos.z*size.x*size.y;

    // Load data from shared memory and do calculations
    float4 init_vector = read_imagef(init_vector_field, sampler, pos);

    float3 v = SNORM16_TO_FLOAT_3(vload3(offset, read_vector_field));
    float3 fx1 = SNORM16_TO_FLOAT_3(vload3(offset+1, read_vector_field));
    float3 fx_1 = SNORM16_TO_FLOAT_3(vload3(offset-1, read_vector_field));
    float3 fy1 = SNORM16_TO_FLOAT_3(vload3(offset+size.x, read_vector_field));
    float3 fy_1 = SNORM16_TO_FLOAT_3(vload3(offset-size.x, read_vector_field));
    float3 fz1 = SNORM16_TO_FLOAT_3(vload3(offset+size.x*size.y, read_vector_field));
    float3 fz_1 = SNORM16_TO_FLOAT_3(vload3(offset-size.x*size.y, read_vector_field));
    
    // Update the vector field: Calculate Laplacian using a 3D central difference scheme
float3 v2;
v2.x = -6*v.x;
v2.y = -6*v.y;
v2.z = -6*v.z;
    float3 laplacian = v2 + fx1 + fx_1 + fy1 + fy_1 + fz1 + fz_1;

    v += mu*laplacian - (v - init_vector.xyz)*(init_vector.x*init_vector.x+init_vector.y*init_vector.y+init_vector.z*init_vector.z);

    vstore3(FLOAT_TO_SNORM16_3(v), writePos.x+writePos.y*size.x+writePos.z*size.x*size.y, write_vector_field);

}

__kernel void GVF3DInit(
		__read_only image3d_t vectorFieldImage,
		__global VECTOR_FIELD_TYPE * vectorField
		) {
    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    vstore3(FLOAT_TO_SNORM16_3(read_imagef(vectorFieldImage, sampler, pos).xyz), LPOS(pos), vectorField);
}

//__kernel void GVF3DFinish(__global float * vectorField, __global float * vectorField2, __global float * sqrMag) {
__kernel void GVF3DFinish(
		__global VECTOR_FIELD_TYPE * vectorField,
		__global VECTOR_FIELD_TYPE * vectorField2
		) {
    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    float4 v;
    v.xyz = SNORM16_TO_FLOAT_3(vload3(LPOS(pos), vectorField));
    v.w = 0;
    v.w = length(v) > 0.0f ? length(v) : 1.0f;
    vstore4(FLOAT_TO_SNORM16_4(v), LPOS(pos), vectorField2);
    //sqrMag[LPOS(pos)] = v.w;
}




#define MAX(a, b) ((a)>(b)?(a):(b))

#define SIZE 3

float hypot2(float x, float y) {
  return sqrt(x*x+y*y);
}

// Symmetric Householder reduction to tridiagonal form.

void tred2(float V[SIZE][SIZE], float d[SIZE], float e[SIZE]) {

//  This is derived from the Algol procedures tred2 by
//  Bowdler, Martin, Reinsch, and Wilkinson, Handbook for
//  Auto. Comp., Vol.ii-Linear Algebra, and the corresponding
//  Fortran subroutine in EISPACK.

  for (int j = 0; j < SIZE; j++) {
    d[j] = V[SIZE-1][j];
  }

  // Householder reduction to tridiagonal form.

  for (int i = SIZE-1; i > 0; i--) {

    // Scale to avoid under/overflow.

    float scale = 0.0f;
    float h = 0.0f;
    for (int k = 0; k < i; k++) {
      scale = scale + fabs(d[k]);
    }
    if (scale == 0.0f) {
      e[i] = d[i-1];
      for (int j = 0; j < i; j++) {
        d[j] = V[i-1][j];
        V[i][j] = 0.0f;
        V[j][i] = 0.0f;
      }
    } else {

      // Generate Householder vector.

      for (int k = 0; k < i; k++) {
        d[k] /= scale;
        h += d[k] * d[k];
      }
      float f = d[i-1];
      float g = sqrt(h);
      if (f > 0) {
        g = -g;
      }
      e[i] = scale * g;
      h = h - f * g;
      d[i-1] = f - g;
      for (int j = 0; j < i; j++) {
        e[j] = 0.0f;
      }

      // Apply similarity transformation to remaining columns.

      for (int j = 0; j < i; j++) {
        f = d[j];
        V[j][i] = f;
        g = e[j] + V[j][j] * f;
        for (int k = j+1; k <= i-1; k++) {
          g += V[k][j] * d[k];
          e[k] += V[k][j] * f;
        }
        e[j] = g;
      }
      f = 0.0f;
      for (int j = 0; j < i; j++) {
        e[j] /= h;
        f += e[j] * d[j];
      }
      float hh = f / (h + h);
      for (int j = 0; j < i; j++) {
        e[j] -= hh * d[j];
      }
      for (int j = 0; j < i; j++) {
        f = d[j];
        g = e[j];
        for (int k = j; k <= i-1; k++) {
          V[k][j] -= (f * e[k] + g * d[k]);
        }
        d[j] = V[i-1][j];
        V[i][j] = 0.0f;
      }
    }
    d[i] = h;
  }

  // Accumulate transformations.

  for (int i = 0; i < SIZE-1; i++) {
    V[SIZE-1][i] = V[i][i];
    V[i][i] = 1.0f;
    float h = d[i+1];
    if (h != 0.0f) {
      for (int k = 0; k <= i; k++) {
        d[k] = V[k][i+1] / h;
      }
      for (int j = 0; j <= i; j++) {
        float g = 0.0f;
        for (int k = 0; k <= i; k++) {
          g += V[k][i+1] * V[k][j];
        }
        for (int k = 0; k <= i; k++) {
          V[k][j] -= g * d[k];
        }
      }
    }
    for (int k = 0; k <= i; k++) {
      V[k][i+1] = 0.0f;
    }
  }
  for (int j = 0; j < SIZE; j++) {
    d[j] = V[SIZE-1][j];
    V[SIZE-1][j] = 0.0f;
  }
  V[SIZE-1][SIZE-1] = 1.0f;
  e[0] = 0.0f;
} 

// Symmetric tridiagonal QL algorithm.

void tql2(float V[SIZE][SIZE], float d[SIZE], float e[SIZE]) {

//  This is derived from the Algol procedures tql2, by
//  Bowdler, Martin, Reinsch, and Wilkinson, Handbook for
//  Auto. Comp., Vol.ii-Linear Algebra, and the corresponding
//  Fortran subroutine in EISPACK.

  for (int i = 1; i < SIZE; i++) {
    e[i-1] = e[i];
  }
  e[SIZE-1] = 0.0f;

  float f = 0.0f;
  float tst1 = 0.0f;
  float eps = pow(2.0f,-52.0f);
  for (int l = 0; l < SIZE; l++) {

    // Find small subdiagonal element

    tst1 = MAX(tst1,fabs(d[l]) + fabs(e[l]));
    int m = l;
    while (m < SIZE) {
      if (fabs(e[m]) <= eps*tst1) {
        break;
      }
      m++;
    }

    // If m == l, d[l] is an eigenvalue,
    // otherwise, iterate.

    if (m > l) {
      int iter = 0;
      do {
        iter = iter + 1;  // (Could check iteration count here.)

        // Compute implicit shift

        float g = d[l];
        float p = (d[l+1] - g) / (2.0f * e[l]);
        float r = hypot2(p,1.0f);
        if (p < 0) {
          r = -r;
        }
        d[l] = e[l] / (p + r);
        d[l+1] = e[l] * (p + r);
        float dl1 = d[l+1];
        float h = g - d[l];
        for (int i = l+2; i < SIZE; i++) {
          d[i] -= h;
        }
        f = f + h;

        // Implicit QL transformation.

        p = d[m];
        float c = 1.0f;
        float c2 = c;
        float c3 = c;
        float el1 = e[l+1];
        float s = 0.0f;
        float s2 = 0.0f;
        for (int i = m-1; i >= l; i--) {
          c3 = c2;
          c2 = c;
          s2 = s;
          g = c * e[i];
          h = c * p;
          r = hypot2(p,e[i]);
          e[i+1] = s * r;
          s = e[i] / r;
          c = p / r;
          p = c * d[i] - s * g;
          d[i+1] = h + s * (c * g + s * d[i]);

          // Accumulate transformation.

          for (int k = 0; k < SIZE; k++) {
            h = V[k][i+1];
            V[k][i+1] = s * V[k][i] + c * h;
            V[k][i] = c * V[k][i] - s * h;
          }
        }
        p = -s * s2 * c3 * el1 * e[l] / dl1;
        e[l] = s * p;
        d[l] = c * p;

        // Check for convergence.

      } while (fabs(e[l]) > eps*tst1);
    }
    d[l] = d[l] + f;
    e[l] = 0.0f;
  }
  
  // Sort eigenvalues and corresponding vectors.

  for (int i = 0; i < SIZE-1; i++) {
    int k = i;
    float p = d[i];
    for (int j = i+1; j < SIZE; j++) {
      if (fabs(d[j]) < fabs(p)) {
        k = j;
        p = d[j];
      }
    }
    if (k != i) {
      d[k] = d[i];
      d[i] = p;
      for (int j = 0; j < SIZE; j++) {
        p = V[j][i];
        V[j][i] = V[j][k];
        V[j][k] = p;
      }
    }
  }
}

void eigen_decomposition(float A[SIZE][SIZE], float V[SIZE][SIZE], float d[SIZE]) {
  float e[SIZE];
  for (int i = 0; i < SIZE; i++) {
    for (int j = 0; j < SIZE; j++) {
      V[i][j] = A[i][j];
    }
  }
  tred2(V, d, e);
  tql2(V, d, e);
}


__kernel void GVFgaussSeidel(
        __read_only image3d_t r,
        __read_only image3d_t sqrMag,
        __private float mu,
        __private float spacing,
        __read_only image3d_t v_read,
        __global VECTOR_FIELD_TYPE * v_write
        ) {
    int4 writePos = {
        get_global_id(0),
        get_global_id(1),
        get_global_id(2),
        0
    };
    // Enforce mirror boundary conditions
    int4 size = {get_global_size(0), get_global_size(1), get_global_size(2), 0};
    int4 pos = writePos;
    pos = select(pos, (int4)(2,2,2,0), pos == (int4)(0,0,0,0));
    pos = select(pos, size-3, pos >= size-1);

    // Calculate manhatten address
    int i = pos.x+pos.y+pos.z;

        // Compute red and put into v_write
        if(i % 2 == 0) {
            float value = native_divide(2.0f*mu*(
                    read_imagef(v_read, sampler, pos + (int4)(1,0,0,0)).x+
                    read_imagef(v_read, sampler, pos - (int4)(1,0,0,0)).x+
                    read_imagef(v_read, sampler, pos + (int4)(0,1,0,0)).x+
                    read_imagef(v_read, sampler, pos - (int4)(0,1,0,0)).x+
                    read_imagef(v_read, sampler, pos + (int4)(0,0,1,0)).x+
                    read_imagef(v_read, sampler, pos - (int4)(0,0,1,0)).x
                    ) - 2.0f*spacing*spacing*read_imagef(r, sampler, pos).x,
                    12.0f*mu+spacing*spacing*read_imagef(sqrMag, sampler, pos).x);
            v_write[LPOS(writePos)] = FLOAT_TO_SNORM16(value);
        }
}

__kernel void GVFgaussSeidel2(
        __read_only image3d_t r,
        __read_only image3d_t sqrMag,
        __private float mu,
        __private float spacing,
        __read_only image3d_t v_read,
        __global VECTOR_FIELD_TYPE * v_write
        ) {
    int4 writePos = {
        get_global_id(0),
        get_global_id(1),
        get_global_id(2),
        0
    };
    // Enforce mirror boundary conditions
    int4 size = {get_global_size(0), get_global_size(1), get_global_size(2), 0};
    int4 pos = writePos;
    pos = select(pos, (int4)(2,2,2,0), pos == (int4)(0,0,0,0));
    pos = select(pos, size-3, pos >= size-1);

    // Calculate manhatten address
    int i = pos.x+pos.y+pos.z;

        if(i % 2 == 0) {
            // Copy red
            float value = read_imagef(v_read, sampler, pos).x;
            v_write[LPOS(writePos)] = FLOAT_TO_SNORM16(value);
        } else {
            // Compute black
                float value = native_divide(2.0f*mu*(
                    read_imagef(v_read, sampler, pos + (int4)(1,0,0,0)).x+
                    read_imagef(v_read, sampler, pos - (int4)(1,0,0,0)).x+
                    read_imagef(v_read, sampler, pos + (int4)(0,1,0,0)).x+
                    read_imagef(v_read, sampler, pos - (int4)(0,1,0,0)).x+
                    read_imagef(v_read, sampler, pos + (int4)(0,0,1,0)).x+
                    read_imagef(v_read, sampler, pos - (int4)(0,0,1,0)).x
                    ) - 2.0f*spacing*spacing*read_imagef(r, sampler, pos).x,
                    12.0f*mu+spacing*spacing*read_imagef(sqrMag, sampler, pos).x);
            v_write[LPOS(writePos)] = FLOAT_TO_SNORM16(value);
        }
}


__kernel void addTwoImages(
        __read_only image3d_t i1,
        __read_only image3d_t i2,
        __global VECTOR_FIELD_TYPE * i3
        ) {
    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    float v = read_imagef(i1,sampler,pos).x+read_imagef(i2,sampler,pos).x;
    i3[LPOS(pos)] = FLOAT_TO_SNORM16(v);
}


__kernel void createSqrMag(
        __read_only image3d_t vectorField,
        __global VECTOR_FIELD_TYPE * sqrMag
        ) {
    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};

    const float4 v = read_imagef(vectorField, sampler, pos);

    float mag = v.x*v.x+v.y*v.y+v.z*v.z;
    sqrMag[LPOS(pos)] = FLOAT_TO_SNORM16(mag);
}

__kernel void MGGVFInit(
        __read_only image3d_t vectorField,
        __global VECTOR_FIELD_TYPE * f,
        __global VECTOR_FIELD_TYPE * r,
        __private int component
        ) {

    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};

    const float4 v = read_imagef(vectorField, sampler, pos);
    const float sqrMag = v.x*v.x+v.y*v.y+v.z*v.z;
    float f_value, r_value;
    if(component == 1) {
        f_value = v.x;
        r_value = -v.x*sqrMag;
    } else if(component == 2) {
        f_value = v.y;
        r_value = -v.y*sqrMag;
    } else {
        f_value = v.z;
        r_value = -v.z*sqrMag;
    }

    f[LPOS(pos)] = FLOAT_TO_SNORM16(f_value);
    r[LPOS(pos)] = FLOAT_TO_SNORM16(r_value);
}

__kernel void MGGVFFinish(
        __read_only image3d_t fx,
        __read_only image3d_t fy,
        __read_only image3d_t fz,
        __global VECTOR_FIELD_TYPE * vectorField
        ) {
    const int4 pos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};

    float4 value;
    value.x = read_imagef(fx,sampler,pos).x;
    value.y = read_imagef(fy,sampler,pos).x;
    value.z = read_imagef(fz,sampler,pos).x;
    value.w = length(value.xyz);
    vstore4(FLOAT_TO_SNORM16_4(value), LPOS(pos), vectorField);
}

__kernel void restrictVolume(
        __read_only image3d_t v_read,
        __global VECTOR_FIELD_TYPE * v_write
        ) {
        int4 writePos = {
        get_global_id(0),
        get_global_id(1),
        get_global_id(2),
        0
    };
    // Enforce mirror boundary conditions
    int4 size = {get_global_size(0)*2, get_global_size(1)*2, get_global_size(2)*2, 0};
    int4 pos = writePos*2;
    pos = select(pos, size-3, pos >= size-1);

    const int4 readPos = pos;
    const float value = 0.125*(
            read_imagef(v_read, samplerClamp, readPos+(int4)(0,0,0,0)).x +
            read_imagef(v_read, samplerClamp, readPos+(int4)(1,0,0,0)).x +
            read_imagef(v_read, samplerClamp, readPos+(int4)(0,1,0,0)).x +
            read_imagef(v_read, samplerClamp, readPos+(int4)(0,0,1,0)).x +
            read_imagef(v_read, samplerClamp, readPos+(int4)(1,1,0,0)).x +
            read_imagef(v_read, samplerClamp, readPos+(int4)(0,1,1,0)).x +
            read_imagef(v_read, samplerClamp, readPos+(int4)(1,1,1,0)).x +
            read_imagef(v_read, samplerClamp, readPos+(int4)(1,0,1,0)).x
            );

    v_write[LPOS(writePos)] = FLOAT_TO_SNORM16(value);
}

__kernel void prolongate(
        __read_only image3d_t v_l_read,
        __read_only image3d_t v_l_p1,
        __global VECTOR_FIELD_TYPE * v_l_write
        ) {
    const int4 writePos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    const int4 readPos = convert_int4(floor(convert_float4(writePos)/2.0f));
    const float value = read_imagef(v_l_read, samplerClamp, writePos).x + read_imagef(v_l_p1, samplerClamp, readPos).x;
    v_l_write[LPOS(writePos)] = FLOAT_TO_SNORM16(value);
}

__kernel void prolongate2(
        __read_only image3d_t v_l_p1,
        __global VECTOR_FIELD_TYPE * v_l_write
        ) {
    const int4 writePos = {get_global_id(0), get_global_id(1), get_global_id(2), 0};
    const int4 readPos = convert_int4(floor(convert_float4(writePos)/2.0f));
    v_l_write[LPOS(writePos)] = FLOAT_TO_SNORM16(read_imagef(v_l_p1, samplerClamp, readPos).x);
}

__kernel void residual(
        __read_only image3d_t r,
        __read_only image3d_t v,
        __read_only image3d_t sqrMag,
        __private float mu,
        __private float spacing,
        __global VECTOR_FIELD_TYPE * newResidual
        ) {
    int4 writePos = {
        get_global_id(0),
        get_global_id(1),
        get_global_id(2),
        0
    };
    // Enforce mirror boundary conditions
    int4 size = {get_global_size(0), get_global_size(1), get_global_size(2), 0};
    int4 pos = writePos;
    pos = select(pos, (int4)(2,2,2,0), pos == (int4)(0,0,0,0));
    pos = select(pos, size-3, pos >= size-1);

    const float value = read_imagef(r, samplerClamp, pos).x -
            ((mu*(
                    read_imagef(v, samplerClamp, pos+(int4)(1,0,0,0)).x+
                    read_imagef(v, samplerClamp, pos-(int4)(1,0,0,0)).x+
                    read_imagef(v, samplerClamp, pos+(int4)(0,1,0,0)).x+
                    read_imagef(v, samplerClamp, pos-(int4)(0,1,0,0)).x+
                    read_imagef(v, samplerClamp, pos+(int4)(0,0,1,0)).x+
                    read_imagef(v, samplerClamp, pos-(int4)(0,0,1,0)).x-
                    6*read_imagef(v, samplerClamp, pos).x
                ) / (spacing*spacing))
            - read_imagef(sqrMag, samplerClamp, pos).x*read_imagef(v, samplerClamp, pos).x);

    newResidual[LPOS(writePos)] = FLOAT_TO_SNORM16(value);
}

__kernel void fmgResidual(
        __read_only image3d_t vectorField,
        __read_only image3d_t v,
        __private float mu,
        __private float spacing,
        __private int component,
        __global VECTOR_FIELD_TYPE * newResidual
        ) {
    int4 writePos = {
        get_global_id(0),
        get_global_id(1),
        get_global_id(2),
        0
    };
    // Enforce mirror boundary conditions
    int4 size = {get_global_size(0), get_global_size(1), get_global_size(2), 0};
    int4 pos = writePos;
    pos = select(pos, (int4)(2,2,2,0), pos == (int4)(0,0,0,0));
    pos = select(pos, size-3, pos >= size-1);

    float4 vector = read_imagef(vectorField, sampler, pos);
    float v0;
    if(component == 1) {
        v0 = vector.x;
    } else if(component == 2) {
       v0 = vector.y;
    } else {
       v0 = vector.z;
    }
    const float sqrMag = vector.x*vector.x+vector.y*vector.y+vector.z*vector.z;

    float residue = (mu*(
                    read_imagef(v, samplerClamp, pos+(int4)(1,0,0,0)).x+
                    read_imagef(v, samplerClamp, pos-(int4)(1,0,0,0)).x+
                    read_imagef(v, samplerClamp, pos+(int4)(0,1,0,0)).x+
                    read_imagef(v, samplerClamp, pos-(int4)(0,1,0,0)).x+
                    read_imagef(v, samplerClamp, pos+(int4)(0,0,1,0)).x+
                    read_imagef(v, samplerClamp, pos-(int4)(0,0,1,0)).x-
                    6*read_imagef(v, samplerClamp, pos).x)
                ) / (spacing*spacing);

    const float value = -sqrMag*v0-(residue - sqrMag*read_imagef(v, samplerClamp, pos).x);

    newResidual[LPOS(writePos)] = FLOAT_TO_SNORM16(value);
}


__kernel void initFloatBuffer(
        __global VECTOR_FIELD_TYPE * buffer
        ) {
        buffer[get_global_id(0)] = FLOAT_TO_SNORM16(0.0f);
}

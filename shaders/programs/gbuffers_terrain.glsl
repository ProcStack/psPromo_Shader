// GBuffer - Terrain GLSL
//   Main hub of most things Minecraft
// Written by Kevin Edzenga, ProcStack; 2022-2024
//

#extension GL_ARB_explicit_attrib_location : enable

#ifdef VSH

#include "utils/shadowCommon.glsl"
const float eyeBrightnessHalflife = 4.0f;

#define SEPARATE_AO

#define ONE_TILE 0.015625
#define THREE_TILES 0.046875

#define PI 3.14159265358979323
#include "/shaders.settings"

uniform sampler2D gcolor;
uniform vec3 sunVec;
uniform int moonPhase;
uniform mat4 gbufferModelView;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferProjection;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 upPosition;
uniform vec3 cameraPosition;
uniform float far;

uniform mat3 normalMatrix;

uniform int blockEntityId;
uniform vec2 texelSize;
uniform vec3 chunkOffset;

uniform int worldTime;

uniform float dayNight;
uniform float eyeBrightnessFit;
uniform ivec2 eyeBrightnessSmooth;
uniform vec3 shadowLightPosition;

in vec3 mc_Entity;
in vec2 mc_midTexCoord;
in vec3 vaPosition;
in vec3 vaNormal;
in vec4 vaColor;
in vec4 at_tangent; 
in vec2 vaUV0; // texture
in ivec2 vaUV2; // lightmap

//in vec3 at_velocity; // vertex offset to previous frame                

// -- -- -- -- -- -- -- --

out vec2 texcoord;
out vec2 texcoordmid;
out vec2 lmcoord;
out vec2 texmidcoord;

out vec4 vtexcoordam; // .st for add, .pq for mul


#ifdef OVERWORLD
  out float skyBrightnessMult;
  out float dayNightMult;
  out float sunPhaseMult;
	out vec4 shadowPos;
#endif


out vec4 vPos;
out vec3 vLocalPos;
out vec4 vWorldPos;
out vec3 vNormal;
out float vNormalSunDot;
out float vNormalSunInf;

out vec4 vColor;
out vec4 vAvgColor;
out float vCrossBlockCull;

out float vAlphaMult;
out float vAlphaRemove;

out vec3 vCamViewVec;
out vec3 vWorldNormal;
out vec3 vAnimFogNormal;

out float vShiftUVs;
out float vDetailBlurringMult;
out float vMultiTexelMap;

out float vWorldTime;
out float vIsLava;
out float vCdGlow;
out float vDepthAvgColorInf;
out float vFinalCompare;
out float vColorOnly;
out float vDeltaPow;
out float vDeltaMult;
out float vShadowValid;


// Having some issues with Iris
//   Putting light texture matrix for compatability
const mat4 LIGHT_TEXTURE_MATRIX = mat4(vec4(0.00390625, 0.0, 0.0, 0.0), vec4(0.0, 0.00390625, 0.0, 0.0), vec4(0.0, 0.0, 0.00390625, 0.0), vec4(0.03125, 0.03125, 0.03125, 1.0));

void main() {
  vec3 normal = normalMatrix * vaNormal;
  vec3 basePos = vaPosition + chunkOffset ;
  //vec3 position = mat3(gbufferModelView) * basePos + gbufferModelView[3].xyz;
  vec3 position = (gbufferModelView * vec4(basePos,1.0)).xyz;
	
  vPos = vec4(position,1.0);
  vLocalPos = basePos;
  vWorldPos = vec4( vaPosition, 1.0);
  gl_Position = ftransform(); // hmmmmmm
	
  vWorldNormal = vaNormal;
  vNormal = normalize(normal);
  vNormalSunDot = dot(normalize(shadowLightPosition), vNormal)*1.5-.5;

  float posLen = length(position);
  vNormalSunInf = step(.02,vNormalSunDot)*max(0.0, 1.0-posLen*0.04);
  vAnimFogNormal = normalMatrix*vec3(1.0,0.0,0.0);
  
  vCamViewVec =  normalize((mat3(gbufferModelView) * normalize(vec3(-1.0,0.0,.0)))*vec3(1.0,0.0,1.0));
  

  // -- -- -- -- -- -- -- --
  
  vColor = vaColor;
  
	// Fit 'worldTime' from 0-24000 -> 0-1; Scale x30
	//   worldTime * 0.00004166666 * 30.0 == worldTime * 0.00125
	vWorldTime = float(worldTime)*0.00125;
	
  texcoord = vaUV0;
  
  vec2 midcoord = mc_midTexCoord;
  texcoordmid=midcoord;
  
  // -- -- --
  
  float avgBlend = .5;
  
  ivec2 txlOffset = ivec2(2);
  vec3 mixColor;
  vec4 tmpCd;
  tmpCd = vColor * texture(gcolor, midcoord);
    mixColor = tmpCd.rgb;
  #if (BaseQuality > 1)
  tmpCd = vColor * textureOffset(gcolor, midcoord, ivec2(-txlOffset.x, txlOffset.y) );
    mixColor = mix( mixColor, tmpCd.rgb, avgBlend*tmpCd.a);
  tmpCd = vColor * textureOffset(gcolor, midcoord, ivec2(txlOffset.x, -txlOffset.y) );
    mixColor = mix( mixColor, tmpCd.rgb, avgBlend*tmpCd.a);
  #if (BaseQuality == 2)
  tmpCd = vColor * textureOffset(gcolor, midcoord, ivec2(-txlOffset.x, -txlOffset.y) );
    mixColor = mix( mixColor, tmpCd.rgb, avgBlend*tmpCd.a);
  tmpCd = vColor * textureOffset(gcolor, midcoord, ivec2(-txlOffset.x, txlOffset.y) );
    mixColor = mix( mixColor, tmpCd.rgb, avgBlend*tmpCd.a);
  #endif
  #endif
  //mixColor = mix( vec3(length(vColor.rgb)), mixColor, step(.1, length(mixColor)) );
  mixColor = mix( vec3(vColor.rgb), mixColor, step(.1, mixColor.r+mixColor.g+mixColor.b) );

  vAvgColor = vec4( mixColor, vColor.a); // 1.0);


  lmcoord = vaUV0;//vec2(vaUV2);

  lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;

  // Get atlas shift & limits for detail blurring
  vec2 texcoordminusmid = texcoord.xy-midcoord;
  texmidcoord = midcoord;
  vtexcoordam.pq = abs(texcoordminusmid)*2.0;
  vtexcoordam.st = min(texcoord.xy ,midcoord-texcoordminusmid);


  // -- -- -- -- -- -- -- --
	

#ifdef OVERWORLD
  
  // Shadow Prep --
	// Invert vert  modelVert positions 
  float depth = min(1.5, length(position.xyz)*.015 );
  vec3 shadowPosition = mat3(gbufferModelViewInverse) * position + gbufferModelViewInverse[3].xyz;
  float shadowPushAmmount =  (depth*.2 + .00030 ) ;
	
  vec3 shadowNormal = mat3(shadowProjection) * mat3(shadowModelView) * gl_Normal;
	float sNormRef = max(abs(shadowNormal.x), abs(shadowNormal.z) );
	
	// `+ (0.75-depth*.55)` is scalping fixes
	sNormRef = max( -shadowNormal.y*depth, sNormRef + (0.75+depth*.55	) );
  shadowPushAmmount *= sNormRef;
  vec3 shadowPush = shadowNormal*shadowPushAmmount ;
  
  shadowPos.xyz = mat3(shadowModelView) * (shadowPosition.xyz+shadowPush) + shadowModelView[3].xyz;
  vec3 shadowProjDiag = diagonal3(shadowProjection);
  shadowPos.xyz = (shadowProjDiag * shadowPos.xyz + shadowProjection[3].xyz);
  shadowPos.w = 1.0;

  vShadowValid=step(abs(shadowPos.x),1.0)*step(abs(shadowPos.y),1.0);
	
  #if ( DebugView == 3 ) // Debug Vision : Shadow Debug
		// Verts push out on the left side of the screen
    //   Showing how far its sampling for the shadow base value
    position = mat3(gbufferModelView) * (shadowPosition.xyz+shadowPush*clamp(1.0-position.x,0.0,1.0)) + gbufferModelView[3].xyz;
  #endif


	// Sun Moon Influence
	skyBrightnessMult = 1.0;
	dayNightMult = 0.0;
	sunPhaseMult = 1.0;

	// Sky Influence
	//   TODO : Move to 
	skyBrightnessMult=eyeBrightnessSmooth.y * 0.004166666666666666; //  1.0/240.0
	//skyBrightnessMult=eyeBrightnessFit;
	
	// Sun Influence
	sunPhaseMult = max(0.0,1.0-max(0.0,dayNight)*2.0);
	//sunPhaseMult = 1.0-(sunPhaseMult*sunPhaseMult*sunPhaseMult);
	
	
	// Moon Influence
	float moonPhaseMult = min(1.0,float(mod(moonPhase+4,8))*.125);
	moonPhaseMult = moonPhaseMult - max(0.0, moonPhaseMult-0.50)*2.0;
	moonPhaseMult = moonPhaseMult*.28 + .075; // Moon's shadowing multiplier

	dayNightMult = mix( 1.0, moonPhaseMult, sunPhaseMult);
  
#endif
  
  
  //gl_Position = toClipSpace3(gbufferProjection, position);
  //gl_Position = ftransform();
  //gl_Position = gbufferProjection * vec4( position, 1.0);
  
  
  
  // -- -- -- -- -- -- -- --
  
  
	// Shift the "edge" of the texture to the center
	//   Only needed for grass_block and dirt so far
	vShiftUVs = 0.0;
  
  vAlphaMult=1.0;
	
  vCdGlow=0.0;
  vColorOnly=0.0;
	
  vFinalCompare = mc_Entity.x == 811 ? 0.0 : 1.0;
  vFinalCompare = mc_Entity.x == 901 ? 0.0 : vFinalCompare;

	// -- -- --

  vIsLava=0.0;
  vCrossBlockCull=0.0;
	
	// -- -- --
	
  // Leaves
  vAlphaRemove = 0.0;
	
	// -- -- --
	
  // Depth-based texture detail smoothing
  vDepthAvgColorInf = 1.0;
	
	// -- -- --
	
  // Ore Detail Blending Mitigation
	// `vDeltaMult` - How strongly details are found in blocks to blur
	//                  (colorB-colorA)*vDeltaMult
	// `vDeltaPow` - Tighten the Bluring around those details from `vDeltaMult`
	//                 Higher is tigher, 0 - 2 is safe; try 10+ though 
	//  ```
	//  pow(length(outCd-vAvgColor),vDeltaPow+light)*vDeltaMult*depth
	//  ```
  vDeltaMult=3.0;
  vDeltaPow=1.8;

	// -- -- --


  // Single plane cross blocks;
  //   Grass, flowers, etc.
  //vCamViewVec=vec3(0.0);
    /*
  if (mc_Entity.x == 801){
  
    //vCrossBlockCull = abs(dot(vec3(vWorldNormal.x, 0.0, vWorldNormal.z),normalize(vec3(vPos.x, 0.0, vPos.z)) ));
    vCrossBlockCull = abs(dot(vec3(vWorldNormal.x, 0.0, vWorldNormal.z),normalize(vec3(1.0, 0.0, 1.0)) ));
    //vCrossBlockCull = abs( dot( normalize(vLocalPos.xyz), normalize(vec3(1.0, 0.0, 1.0)) ) );
    vCrossBlockCull = abs( dot( normalize(vec3(vWorldNormal.x, 0.0, vWorldNormal.z)), normalize(vec3(vLocalPos.x, 0.0, vLocalPos.z)) ) );
    //vCrossBlockCull =  dot( normalize(vLocalPos.xyz), normalize(vec3(1.0, 0.0, 1.0)) )*.5+.5;
    
    //vAlphaMult=clamp( (vCrossBlockCull+.5)*10.0, 0.0, 1.0 );
    //vAlphaMult=step(.5, vCrossBlockCull);
    
    float alphaStep = abs(vCrossBlockCull-.5)-.2;

    vCrossBlockCull=step( .0, alphaStep );
    float blerg = abs(dot(vec3(vWorldNormal.x, 0.0, vWorldNormal.z),vec3(0.707107,0.0,0.707107) ));
    blerg = step(.5, abs(dot(vec3(vCamViewVec.x, 0.0, vCamViewVec.z),vec3(0.707107,0.0,0.707107) )) );
    //blerg = normalize(vec3(vPos.x, 0.0, vPos.z));
    //blerg = dot( normalize((cameraPosition - gbufferModelView[3].xyz)*vec3(1.0,0.0,1.0)), vec3(0.707107,0.0,0.707107) );
    //vCrossBlockCull=blerg;
    //vCamViewVec = normalize( basePos.xyz );
    //vCamViewVec = normalize((gbufferProjection[3].xyz)*vec3(1.0,0.0,1.0));
  vec3 crossNorm = abs(normalize((vWorldNormal.xyz)*vec3(1.0,0.0,1.0)));
  //vCamViewVec = normalize((vCamViewVec.xyz)*vec3(1.0,0.0,1.0));
  //vCamViewVec = vec3( abs(dot(vCamViewVec,crossNorm)) );
  //  vCamViewVec = vec3( abs(dot(vCamViewVec,crossNorm)) );
    vCamViewVec = vec3( abs(dot(vCamViewVec,crossNorm)) );
    vCamViewVec = cross(vCamViewVec,crossNorm);
    vCamViewVec = vec3( abs(dot( cross(vCamViewVec,crossNorm), vec3(0.707107,0.0,0.707107) )) );
    //vCamViewVec = vec3( step(.5, abs(dot(vec3(vNormal.x, 0.0, vCamViewVec.z),vec3(0.707107,0.0,0.707107) )) ) );
    
//    normalMatrix * vaNormal;
    vCamViewVec = vec3( dot( normalMatrix* vaNormal, vaNormal ) );
    //vCrossBlockCull=step( .5, vCrossBlockCull );
    
    
    
  //position = mat3(gbufferModelViewInverse) * position + gbufferModelViewInverse[3].xyz;
    
    vCamViewVec = mat3(gbufferModelViewInverse) * vec3(0.0,0.0,1.0) + gbufferModelViewInverse[3].xyz;
    vCamViewVec = inverse(normalMatrix) * normalize( vCamViewVec*vec3(1.0,0.0,1.0) );
    vec4 refPos = (gbufferProjectionInverse * gbufferModelViewInverse * basePos)*.5;

    vec3 crossRefVec = normalize( ( vWorldPos.xyz, refPos.xyz )*vec3(1.0,0.0,1.0) );
    vec3 wNormRefVec = normalize( vWorldNormal*vec3(1.0,0.0,1.0) );
    //vCrossBlockCull = 1.0-abs(dot( crossRefVec, wNormRefVec ));
    //vCamViewVec = vec3( step( vCrossBlockCull, .5 ) );
    vCamViewVec = mat3(gbufferModelViewInverse) * vaNormal;
    vCamViewVec = mat3(gbufferProjection) * vaNormal;
    //vCamViewVec = vaNormal;
    //vAlphaMult=vCrossBlockCull;
  }
  */
  
  // Leaves
  if((mc_Entity.x == 810 || mc_Entity.x == 8101) && SolidLeaves ){
    vAvgColor = mc_Entity.x == 810 ? vColor * (vAvgColor.g*.5+.5) : vAvgColor;
    vColor = mc_Entity.x == 8101 ? vAvgColor : vColor;
    
    
    vAlphaRemove = 1.0;
    //shadowPos.w = -2.0;
  }


  if( mc_Entity.x == 801 || mc_Entity.x == 811 || mc_Entity.x == 8014 ){
    vColorOnly = mc_Entity.x == 801 ? 0.85 : 0.0;
    vAvgColor*=vColor;
    vDepthAvgColorInf=vColor.r;
  }

// Flowers; For more distinct colors
  if( mc_Entity.x == 802 ){
    vAvgColor*=vColor;
    vDepthAvgColorInf=0.0;
  }
	
  // Slab & Stairs with detail blending UV issues
  //if( mc_Entity.x == 812 ){
  //}
  
	
	// `vDeltaMult` - How strongly details are found in blocks to blur
	//                  (colorB-colorA)*vDeltaMult
	// `vDeltaPow` - Tighten the Bluring around those details from `vDeltaMult`
	//                 Higher is sharper approach to the edge
	//                   0 - 2 is safe; try 10+ though 
	//  ```
	//  pow(length(outCd-vAvgColor),vDeltaPow+light)*vDeltaMult*depth
	//  ```
	
  // Ore Detail Blending Mitigation
  if( mc_Entity.x == 811 ){ // Dirt Grass
		vShiftUVs = 0.5;
    vDeltaMult=50.5;
		vDeltaPow=4.53;
	}else if( mc_Entity.x == 247  ){ // Glowstone
    vDeltaMult=2.5;
		vDeltaPow=1.5;
		vAvgColor=vec4(0.729, 0.557, 0.318,0.0);
		
		vDepthAvgColorInf=1.0;
		vColorOnly=1.0;
		
		// Glow boost, yeah, should be a different variable
		vIsLava = 0.4; 
		
	}else if( mc_Entity.x == 103 ){ // Most ores
		vDeltaMult=5.0;
    vDeltaPow=0.80;
  }else if( mc_Entity.x == 104 ){ // Diamonds
		vDeltaMult=1.5;
    vDeltaPow=0.80;
		vAvgColor=vec4(0.5,0.5,0.5,1.0);
  }else if( mc_Entity.x == 105 ){ // Powerder Snow & Lapis
    vDeltaPow=0.90;
		vAvgColor+=vec4(0.1,0.1,0.12,0.0);
  }else if( mc_Entity.x == 115 ){ // Birdh Wood & Log
    vDeltaMult=1.10;
    vDeltaPow=4.0;
  }else if( mc_Entity.x == 303 ){ // Nether Quartz Ore
		vAvgColor = vec4( 0.29, 0.107, 0.107, 1.0 );
		vDeltaMult=4.0;
		vDeltaPow=2.8;
  }else if( mc_Entity.x == 304 ){ // Hoppers
		vAvgColor = vec4( 0.25, .25, .25, 1.0 );
		vDeltaMult=4.0;
		vDeltaPow=2.8;
  }else if( mc_Entity.x == 305 ){ // Redstone Lamp : lit=false
		vDeltaMult=3.0;
		vDeltaPow=.5;
  }else if( mc_Entity.x == 306 ){ // Wool & its colors
		vAvgColor *= vec4( vec3(.75), 1.0 );
		vDeltaMult=1.5;
		vDeltaPow=1.;
  }else

	// Color corrections
	if( mc_Entity.x == 302 ){ // soul sand
		vAvgColor = vec4( 0.224, 0.135, 0.114, 1.0 );
		vColor = vec4( 0.224, 0.135, 0.114, 1.0 );
		
		vAvgColor = vec4( 0.324, 0.235, 0.214, 1.0 );
		vColor = vec4( 0.324, 0.235, 0.214, 1.0 );
		vDeltaPow = 0.050;
		vDeltaMult = 5.0;
	}else if( mc_Entity.x == 304 ){
		// Magick numbers, boo!
		vAvgColor.rgb = vec3(dot(vAvgColor.rgb, vec3(0.299, 0.087, 0.214)));
	}
	
	// -- -- --
	
	
  // -- -- -- -- -- -- -- -- -- -- -- --
  // -- Added Glow Influece by Id # - -- --
  // -- -- -- -- -- -- -- -- -- -- -- -- -- --
	// Isolate Glow Overide blocks
	//   The 2## blocks are turned 0-100% of MORE glow
	//     Usable Range : 201-299 -> 1-99% added glow 
	//     <200 && >299 turn into 0%
	//       Go out of range?
	//         Get the ban hammer!
	//       https://youtu.be/eIn9aVbdFlY
	//  
  // Stuff like End Rods, Soul Lanterns, Glowstone,
	//   Redstone Lamp, Sea Lantern, Shroomlight, etc.
	// This is in addition to all-block lighting + texture based glow
	
  float worldGlowMult = GlowMult_Overworld;
  float worldIsLava = ColorBoost_IsLava;
	
#ifdef NETHER
		worldGlowMult = GlowMult_Nether;
		worldIsLava = ColorBoost_IsLavaNether;
#endif

	float idFitToGlow = float( mc_Entity.x - 200 )*.01;
	float idFitInfluence = step(0.00001, idFitToGlow) * step(idFitToGlow,.9999);
	
	idFitToGlow *= .9;
	
	vCdGlow = idFitToGlow * idFitInfluence * worldGlowMult;
	
	//vDepthAvgColorInf = 0.20+idFitToGlow; // Id based maybe? ::smirks::
	//                               This will save further calcs in frag

  // Fire / Soul Fire
  if( mc_Entity.x == 280 ){
    vCdGlow=idFitToGlow * worldGlowMult;
    vColor+=vColor*.05;
    //vAvgColor = vec4( .8, .6, .0, 1.0 );
    
    //vDepthAvgColorInf =  0.0;
  }

  // Lava
  if( mc_Entity.x == 701 ){
    vIsLava = .5+clamp(gl_Position.w*.05+.01, 0.0,0.5);
    vCdGlow = worldIsLava * worldGlowMult;
		
    vColor.rgb = mix( vAvgColor.rgb, texture(gcolor, midcoord).rgb, .5 );
		//vAvgColor.rgb = vColor.rgb;
  }
	
	// Chorus Flower/Plants
  vAvgColor.rgb = mc_Entity.x == 251 || mc_Entity.x == 267 
										? (vAvgColor.rgb*.3+vColor.rgb*.6) * vec3(.42,.3,.42)
										: vAvgColor.rgb;

}

#endif






/*  -- -- -- -- -- -- -- -- -- -- -- --  */
/*  -- -- -- -- -- -- -- -- -- -- -- --  */
/*  -- -- -- -- -- -- -- -- -- -- -- --  */






#ifdef FSH


#define gbuffers_terrain

/* RENDERTARGETS: 0,1,2,7,6 */
layout(Location = 0) out vec4 outCd;
layout(Location = 1) out vec4 outDepthGlow;
layout(Location = 2) out vec4 outNormal;
layout(Location = 3) out vec4 outLighting;
layout(Location = 4) out vec4 outGlow;


/* --
const int gcolorFormat = RGBA8;
const int gdepthFormat = RGBA16;
const int gnormalFormat = RGB10_A2;
 -- */

#include "/shaders.settings"
#include "utils/shadowCommon.glsl"
#include "utils/mathFuncs.glsl"
#include "utils/texSamplers.glsl"
#include "utils/stylization.glsl"


uniform sampler2D gcolor;
uniform sampler2D lightmap;
uniform sampler2D normals;
uniform sampler2D noisetex; // Custom Texture; textures/SoftNoise_1k.jpg
uniform int fogMode;
uniform vec3 fogColor;
uniform vec3 skyColor;
uniform vec3 sunVec;
uniform vec3 cameraPosition;
uniform int isEyeInWater;
uniform float BiomeTemp;
uniform float nightVision;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;


uniform float viewWidth;
uniform float viewHeight;

uniform float near;
uniform float far;
uniform sampler2D gaux1;
uniform sampler2DShadow shadowtex0;
uniform sampler2DShadow shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D shadowcolor1;
uniform int shadowQuality;

uniform vec2 texelSize;
uniform float aspectRatio;


// To Implement
//uniform float wetness;  //rainStrength smoothed with wetnessHalfLife or drynessHalfLife
//uniform int fogMode;
//fogMode==GL_LINEAR
//fogMode==GL_EXP
//fogMode==GL_EXP2
//uniform float fogStart;
//uniform float fogEnd;
//uniform int fogShape;
//uniform float fogDensity;
//uniform int heldBlockLightValue;
//uniform int heldBlockLightValue2;
uniform float rainStrength;


uniform vec3 upPosition;

// Glow Pass Varyings --
in float txGlowThreshold;
// -- -- -- -- -- -- -- --

in vec4 vColor;
in vec2 texcoord;
in vec2 texcoordmid;
in vec2 lmcoord;

in vec2 texmidcoord;
in vec4 vtexcoordam; // .st for add, .pq for mul


#ifdef OVERWORLD
  in float skyBrightnessMult;
  in float dayNightMult;
  in float sunPhaseMult;
	in vec4 shadowPos;
#endif

uniform vec3 shadowLightPosition;
uniform float dayNight;
uniform float sunMoonShadowInf;
uniform int worldTime;

in float vAlphaMult;
in float vAlphaRemove;
in float vColorOnly;

in vec3 vCamViewVec;
in vec4 vPos;
in vec3 vLocalPos;
in vec4 vWorldPos;
in vec3 vNormal;
in vec3 vWorldNormal;
in float vNormalSunDot;
in float vNormalSunInf;
in vec3 vAnimFogNormal;

in float vShiftUVs;
in vec4 vAvgColor;
in float vCrossBlockCull;

in float vWorldTime;
in float vIsLava;
in float vCdGlow;
in float vDepthAvgColorInf;
in float vFinalCompare;
in float vDeltaPow;
in float vDeltaMult;
in float vShadowValid;

void main() {

	vec2 tuv = texcoord;
	vec4 baseTxCd=texture(gcolor, tuv);
	
	vec4 txCd=vec4(1.0,1.0,0.0,1.0);

	vec2 screenSpace = (vPos.xy/vPos.z)  * vec2(aspectRatio);

	vec2 luv = lmcoord;
	float outDepth = min(.9999,gl_FragCoord.w);
	float isLava = vIsLava;
	vec4 avgShading = vAvgColor;
	float avgDelta = 0.0;

	// -- -- -- -- -- -- --

	float rainStrengthInv = 1.0-rainStrength;

	// -- -- -- -- -- -- --
	
	// vWorldPos.y = -64 to 320
	// 1/255 = 0.003921568627451
	// 1/384 = 0.002604166666666
	float wYMult = (1.0+abs(screenSpace.x)*.03-rainStrength*0.01);
	float worldPosYFit = clamp(vWorldPos.y*(0.0075*wYMult*wYMult), 0.0, 1.0);
	worldPosYFit = max(0.0, 1.0-max(0.0,(1.0-worldPosYFit)*1.25)*.7 );

	

	float skyBrightness = 1.0;
	
	// -- -- -- -- -- -- --
	
	vec4 baseCd=baseTxCd;
	
	
	// Alpha Test
	baseTxCd.a = max(baseTxCd.a, vAlphaRemove) * vColor.a ;

	#if( DebugView == 4 )
		baseTxCd.a = mix(baseTxCd.a, 1.0, step(screenSpace.x,.0)*vAlphaRemove);
	#else
		baseTxCd.a = mix(baseTxCd.a, 1.0, vAlphaRemove) * vAlphaMult;
	#endif

	if ( baseTxCd.a  < .02 ){
		discard;
	}
	

	// -- -- -- -- -- -- --
	
	// Texture Sampler
	
	// TODO : There's gotta be a better way to do this...
	//          - There is, just gotta change it over
	if ( DetailBlurring > 0.0 ){
		// Split Screen "Blur Comparison" Debug View
		#if ( DebugView == 1 )
			float debugDetailBlurring = clamp((screenSpace.y/(aspectRatio*.8))*.5+.5,0.0,1.0)*2.0;
			//debugDetailBlurring *= debugDetailBlurring;
			debugDetailBlurring = mix( DetailBlurring, debugDetailBlurring, step(screenSpace.x,0.75));
			diffuseSampleXYZ( gcolor, tuv, vtexcoordam, texelSize, vShiftUVs, debugDetailBlurring, baseCd, txCd, avgDelta );
		#else
			vec2 uvLimitPerc = vec2( 1.0, 1.0 ); // Vertical half slab limits is X, Horizontal is Y
			//diffuseSampleXYZFetch( gcolor, tuv, texcoordmid, texelSize, uvLimitPerc, vShiftUVs, DetailBlurring, baseCd, txCd, avgDelta);
			//diffuseSampleXYZFetch( gcolor, tuv, texcoordmid, texelSize, screenSpace.x, baseCd, txCd, avgDelta);
			diffuseSampleXYZ( gcolor, tuv, vtexcoordam, texelSize, vShiftUVs, DetailBlurring, baseCd, txCd, avgDelta );
		#endif
	}else{
		txCd = texture(gcolor, tuv);
	}

	
	vec4 baseBlurColor = txCd;
	
	
// Default Minecraft Lighting
	vec4 lightLumaCd = texture(lightmap, luv);//*.9+.1;
	float lightLumaBase = clamp(luma(lightLumaCd.rgb)*1.2-.13,0.0,1.0);
	
	txCd.rgb = mix(baseCd.rgb, txCd.rgb, avgDelta);
	txCd.rgb = mix(txCd.rgb, vColor.rgb, vAlphaRemove);
	
	
// Glow Baseline Variables
	float glowInf = 0.0;
	vec3 glowCd = vec3(0,0,0);
	glowCd = txCd.rgb*vCdGlow;// * max(0.0, luma(txCd.rgb));
	glowInf = max(0.0, maxComponent(txCd.rgb)*1.5-.9)*vCdGlow;
	
	
// Screen Space UVing and Depth
// TODO : Its a block game.... move the screen space stuff to vert stage
//          Vert interpolation is good enough
	float screenDewarp = length(screenSpace)*0.7071067811865475; //  1 / length(vec2(1.0,1.0))
	screenDewarp*=screenDewarp*.7+.3;
	
// Get scene depth, and make glowy things less depth influenced
	float depth = min(1.0, max(0.0, gl_FragCoord.w+glowInf*.5));
	float depthBias = biasToOne(depth, 9.5);
	
// A bias of .035 for retaining detail closer to camera
	float depthDetailing = clamp(detailDistBias*1.5-depthBias, 0.0, 1.0);

// Side by side of active blurring and no blurring
//   Other shader effects still applied though
	#if ( DebugView == 1 )
		txCd = mix( texture(gcolor, tuv), txCd, step(0.0, screenSpace.x+.75) );
	#endif


// -- -- -- -- -- -- -- --


// Use Light Map Data
	//float lightLuma = clamp((lightLumaBase-.265) * 1.360544217687075, 0.0, 1.0); // lightCd.r;
	//float lightLuma = ( clamp((lightLumaBase) * 1.560544217687075, 0.0, 1.0) ); // lightCd.r;
	float lightLuma = shiftBlackLevels( biasToOne(lightLumaBase) ); // lightCd.r;

	vec3 lightCd = vec3(lightLuma);//vec3(max(lightLumaBase,lightLuma));
	

// -- -- -- -- -- -- -- --


	outCd = vec4(txCd.rgb,1.0) * vec4(vColor.rgb,1.0);

	vec3 outCdAvgRef = outCd.rgb;
	//vec3 cdToAvgDelta = outCdAvgRef.rgb - txCd.rgb; // Strong color changes, ie birch black bark markings
	//float cdToAvgBlender = min(1.0, addComponents( cdToAvgDelta ));
	//outCd.rgb = mix( outCd.rgb, txCd.rgb, max(0.0,cdToAvgBlender-depthBias*.5)*vFinalCompare );
	
	//float avgColorBlender = min(1.0, pow(length(txCd.rgb-vAvgColor.rgb),vDeltaPow+lightLuma*.75)*vDeltaMult*depthBias);
	float avgColorBlender = min(1.0, pow(length(outCd.rgb-vAvgColor.rgb),vDeltaPow+lightLuma)*vDeltaMult*depthBias);
	outCd.rgb =  mix( vAvgColor.rgb, outCd.rgb, avgColorBlender );
	//glowCd = outCd.rgb*vCdGlow;// * max(0.0, luma(txCd.rgb));
	//glowCd = vAvgColor.rgb;// * max(0.0, luma(txCd.rgb));


// -- -- -- -- -- -- -- -- -- -- -- --
// -- Apply Shading To Base Color - -- --
// -- -- -- -- -- -- -- -- -- -- -- -- -- --

	float avgColorMix = depthDetailing*vDepthAvgColorInf;
	avgColorMix = min(1.0, avgColorMix + vAlphaRemove + isLava*(3.0+(1.0-depth)));
	outCd = mix( vec4(outCd.rgb,1.0),  vec4(avgShading.rgb,1.0), min(1.0,avgColorMix+vColorOnly));
	// TODO : Optimize
	vec3 glowBaseCd = mix( outCd.rgb, avgShading.rgb, min(1.0,avgColorMix+vColorOnly));
	//glowCd = glowBaseCd;

// -- -- -- -- -- -- -- --
// Based on shadow lookup from Chocapic13's HighPerformance Toaster
//
  float shadowDist = 0.0;
  float diffuseSun = 1.0;
  float shadowAvg = 1.0;
  vec4 shadowCd = vec4(0.0);
  float reachMult = 0.0;
  
  float toCamNormalDot = dot(normalize(-vPos.xyz*vec3(1.3,1.35,1.3)),vNormal);
  float surfaceShading = 9.0-abs(toCamNormalDot);
		
  vec3 tmpCd = vec3(1.0,0.0,0.0);
	
	float shadowRainStrength = rainStrength;

// -- -- -- -- -- -- -- -- -- -- -- --
// -- Shadow Sampling & Influence - -- --
// -- -- -- -- -- -- -- -- -- -- -- -- -- --

#ifdef OVERWORLD
	
	skyBrightness = skyBrightnessMult;

#if ShadowSampleCount > 0

  vec3 localShadowOffset = shadowPosOffset;
  //localShadowOffset.z *= (skyBrightness*.5+.5);
  //localShadowOffset.z *= min(1.0,outDepth*20.0+.7)*.1+.9;
  //localShadowOffset.z = 0.5 - min( 1.0, (shadowThreshBase + shadowThreshDist*(1.0-depthBias)) * shadowThreshold );
  localShadowOffset.z = 0.5 - min( 1.0, (shadowThreshBase + shadowThreshDist*(1.0-depthBias*depthBias)) * shadowThreshold );
  
  vec4 shadowPosLocal = shadowPos;
  //shadowPosLocal.xy += vCamViewVec.xz;
  
// Implement --	
//  vWorldNormal.y*(1.0-shadowData.b)

  shadowPosLocal = distortShadowShift( shadowPosLocal );
  vec3 projectedShadowPosition = shadowPosLocal.xyz * shadowPosMult;
  float shadowFade = clamp( (1.0-max(abs(shadowPosLocal.x),abs(shadowPosLocal.y))) * shadowEdgeFade, 0.0, 1.0) ;

// Get base shadow value
  float shadowBase=shadow2D(shadowtex0, projectedShadowPosition + localShadowOffset).x; 
	shadowAvg = shadowBase ;
	
// Get base shadow source block color
	projectedShadowPosition = projectedShadowPosition + localShadowOffset;
  shadowCd=texture(shadowcolor0, projectedShadowPosition.xy); 
	
// Get shadow source distance
// Delta of frag shadow distance * shadowDistBiasMult
	vec3 shadowData = texture(shadowcolor1, projectedShadowPosition.xy).rgg;
	shadowData.b = max(0.0, shadowData.g - length(shadowPosLocal.xy) ) * shadowDistBiasMult;
	
	//shadowCd.rgb = mix( vec3(1.0), shadowCd.rgb, shadowFade ); 
	shadowCd.rgb = mix( vec3(1.0), shadowCd.rgb, shadowData.r*shadowFade ); 

// Higher the value, the softer the shadow
//   ...well "softer", distance of multi-sample
  reachMult = min(10.0,  shadowData.b*1.2 + 2.2 );

  reachMult = max(0.0, reachMult - (min(1.0,outDepth*20.0)*.5));


#if ShadowSampleCount == 2
  vec2 posOffset;
  
  for( int x=0; x<axisSamplesCount; ++x){
    posOffset = axisSamples[x]*reachMult*shadowMapTexelSize*skyBrightness;
    projectedShadowPosition = vec3(shadowPosLocal.xy+posOffset,shadowPosLocal.z)
																	* shadowPosMult + localShadowOffset;
  
    shadowAvg = mix( shadowAvg, shadow2D(shadowtex0, projectedShadowPosition).x, axisSamplesFit);
  }
#elif ShadowSampleCount == 3
  vec2 posOffset;
  
  for( int x=0; x<boxSamplesCount; ++x){
    posOffset = boxSamples[x]*reachMult*shadowMapTexelSize;
    projectedShadowPosition = vec3(shadowPosLocal.xy+posOffset,shadowPosLocal.z)
																	* shadowPosMult + localShadowOffset;
    shadowAvg = mix( shadowAvg, shadow2D(shadowtex0, projectedShadowPosition).x, boxSampleFit);
  }
#elif ShadowSampleCount > 3
  vec2 posOffset;
  
  for( int x=0; x<boxSamplesCount; ++x){
    posOffset = boxSamples[x]*reachMult*shadowMapTexelSize;
    projectedShadowPosition = vec3(shadowPosLocal.xy+posOffset,shadowPosLocal.z)
																	* shadowPosMult + localShadowOffset;
    shadowAvg = mix( shadowAvg, shadow2D(shadowtex0, projectedShadowPosition).x, boxSampleFit);
  }
#endif

  
  float shadowDepthInf = clamp( (depth*distancDarkenMult), 0.0, 1.0 );
  shadowDepthInf *= shadowDepthInf;

// Verts not facing the sun should never have non-1.0 shadow values
	//shadowCd.rgb = mix( vec3(1.0), shadowCd.rgb, min(1.0,vNormalSunInf*shadowDepthInf));
	shadowCd.rgb = mix( vec3(1.0), shadowCd.rgb*vNormalSunInf, vNormalSunInf);

// Distance Rolloff
  shadowAvg = shadowAvg + min(1.0, (length(projectedShadowPosition.xy)*.0025)*1.5);//
  
  float shadowInfFit = 0.025;
  float shadowInfFitInv = 40.0; // 1.0/shadowInfFit;
  float shadowSurfaceInf = clamp( (shadowInfFit-(-dot(normalize(shadowLightPosition), vNormal)))
														*shadowInfFitInv*1.5, 0.0, 1.0 );
  
// -- -- --

	shadowRainStrength *= shadowData.b;

// -- -- --

//  Distance influence of surface shading --
//  TODO : !! Cleans up shadow crawl with better values
  shadowAvg = mix( mix(1.0,(shadowAvg*shadowSurfaceInf),vShadowValid), min(shadowAvg,shadowSurfaceInf), shadowAvg*vShadowValid) * skyBrightness * rainStrengthInv * dayNightMult;
	
  // -- -- --
	
  diffuseSun *= mix( max(0.0,shadowDepthInf-rainStrength), shadowAvg, sunMoonShadowInf  );

#endif



// -- -- -- -- -- -- -- --
// -- Lighting & Diffuse - --
// -- -- -- -- -- -- -- -- -- --
	
// Mute Shadows during Rain
	diffuseSun = mix( diffuseSun, 0.50, rainStrength)*skyBrightness;

// The diffuse is the suns influence on the blocks
//   Getting the max reduces hotspots,
//     But that reduces the style I'm going for
//       Work-in-Progress
	lightCd = max( lightCd, diffuseSun);
	
// Mix translucent color
	float lColorMix = clamp( shadowData.r*(1.0-shadowBase)
														* clamp( shadowDepthInf*2.0-1.0, 0.0, 1.0)
														- shadowData.b*.5, 0.0, 1.0 ) * vNormalSunInf ;
	//lightCd = mix( lightCd, lightCd*(fogColor*(1.0-worldPosYFit)+(shadowCd.rgb*.5+.15)*worldPosYFit), lColorMix );
	lightCd = mix( lightCd, (shadowCd.rgb*2.0+.15), lColorMix );

// Strength of final shadow
	outCd.rgb *= mix(max( vec3(min(1.0,shadowAvg+lightLuma*shadowLightInf)), lightCd*shadowMaxSaturation), vec3(1.0),shadowAvg);


	lightLuma = min( maxComponent(lightCd), lightLuma );


// Kill off shadows on sun far side; prevents artifacts
	//lightCd = mix( lightCd, max(lightCd, vec3(shadowAvg))*lightLuma, clamp(shadowAvg*vNormalSunInf,0.0,1.0)) ;
	lightCd = mix( lightCd, max(lightCd, vec3(shadowAvg))*lightLuma, shadowAvg*vNormalSunInf) ;



// Add day/night & to sun normal; w/ Sky Brightness limits
	surfaceShading *= mix( dayNightMult, vNormalSunDot, sunMoonShadowInf*.5+.5 );
	
// WARNING - I could see not knowing why I'm doing this in the future
//             Even reading the code.
//    Sky Brightness influence in the fog color blenderings.
  diffuseSun *= skyBrightnessMult;

#endif
	





// -- -- -- -- -- -- --
// -- Fake Fresnel - -- --
// -- -- -- -- -- -- -- -- --

	float dotToCam = dot(vNormal,normalize(vec3(screenSpace*(1.0-depthBias*.25),1.0)));
	outCd*=mix(1.0, dotToCam, isLava);
	
	

	// Apply Black Level Shift from User Settings
	//   Since those set to 0 would be rather low,
	//     Default is to run black shift with no check.
	// Level Shifting here first, instead of strictly a composite pass to retain more color detail
	//   Felt I'd need to store too many values to buffers for a post process to work well
	//     It didn't make sense to do, for me
	lightCd = shiftBlackLevels( lightCd );
	surfaceShading = max( surfaceShading, lightCd.r );
	surfaceShading = ( surfaceShading * lightCd.r );
	surfaceShading = shiftBlackLevels( surfaceShading );
	


// -- -- -- -- -- -- --
// -- Fog Coloring - -- --
// -- -- -- -- -- -- -- -- --

	vec3 toSkyColor = skyColor;

	// Fog-World Blending Influence
	float fogColorBlend = mix( 0.0, rainStrength, diffuseSun );
  fogColorBlend = clamp( .9+depth+fogColorBlend, .1, 1.0 ) * (1.0-nightVision);
	
	float invRainInf = rainStrengthInv*.2;
	
	fogColorBlend = min( 1.0, (fogColorBlend+invRainInf) * min(1.0,depth*(150.0-rainStrength*145.0*min(1.0,skyBrightness*4.0))) * (1.0-invRainInf) + invRainInf + glowInf);


	vec3 toFogColor = mix( toSkyColor*.5, fogColor*.9+outCd.rgb*.1, depth*.7+.3);
	
	toFogColor = mix( outCd.rgb*(toFogColor*.8)+toFogColor , toFogColor, worldPosYFit*.5)*worldPosYFit;
	
	// Includes `Night Vision` in fogColorBlend
	toFogColor = mix( vec3(1.0), toFogColor, fogColorBlend);


// -- -- -- -- -- -- 


// -- -- -- -- -- -- -- -- -- -- --
// -- Distance Based Color Boost -- --
// -- -- -- -- -- -- -- -- -- -- -- -- --

	depthDetailing = max(0.0, min(1.0,(1.0-(depthBias+(vCdGlow*0.8)))*distantVibrance) ); 
	//surfaceShading = 1.0-(1.0-surfaceShading)*.4;
	
	outCd.rgb += outCd.rgb * depthBias * surfaceShading * depthDetailing  * toFogColor; // -.2;
	

// -- -- -- -- -- -- 
	
    
// -- -- -- -- -- -- -- -- -- -- 
// End Logic; Animated Fog  - -- --
// -- -- -- -- -- -- -- -- -- -- -- --

// TODO : MOVE TO POST PROCESSING ... ya dingus
#ifdef THE_END

	float depthEnd = min(1.0, max(0.0, outDepth*2.5+lightLumaBase*.5-screenDewarp*.005-.005));
	depthEnd = 1.0-(1.0-depthEnd)*(1.0-depthEnd);
	depthEnd = depthEnd*.7+.3;
	
// Fit lighting 0-1
	float lightShift=.47441;
	float lightShiftMult=1.9026237181072698; // 1.0/(1.0-lightShift)
	float lightInf = clamp( (max((lightCd.r-.2)*1.0,lightLumaBase)-lightShift)
													*lightShiftMult
													*min(depthEnd,1.0), 0.0, 1.0 );
												
	vec3 endFogCd = skyColor;
	
	float timeOffset = (float(worldTime)*0.00004166666)*30.0;
	
	vec3 worldPos = (abs(cameraPosition+vLocalPos.xyz)*vec3(.09,.06,.05)*.01);
	worldPos = ( worldPos+texture( noisetex, fract(worldPos.xz+worldPos.yy)).rgb );

	
// RGB Depth Based Noise for final influence
	vec3 noiseX = texture( noisetex, fract(worldPos.xy*depthEnd*2.5 + (timeOffset*vec2(.25,.75)))).rgb;
	//vec3 noiseZ = texture( noisetex, fract(worldPos.yz+noiseX.rg*.1 + vec2(timeOffset) )).rgb;
	
	endFogCd = mix( noiseX*endFogCd * (1.0-depthEnd)+depthEnd, vec3(lightLumaBase), lightInf );
	outCd.rgb *= .5 + noiseX*.5;
	toSkyColor = skyColor;//outCd.rgb ;
	fogColorBlend=depthEnd;//+lightLumaBase*.1;

#endif


// -- -- -- -- -- -- --
// -- Fog Vision - -- --
// -- -- -- -- -- -- -- -- --

vec3 skyGreyCd = outCd.rgb;
float skyGreyInf = 0.0;
	
// Fog when Player in Water 
	if( isEyeInWater == 1 ){ 
		float smoothDepth=min(1.0, smoothstep(.01,.1,depth));
		// General brightness under water
			
		outCd.rgb *=  smoothDepth+lightLuma*.5+glowInf;
		outCd.rgb *=  toFogColor*(1.0+lightLuma*lightLuma*.3)+(smoothDepth*.35+.25);
		
// Fog when Player in Lava 
	}else if( isEyeInWater > 1 ){
		depthBias = depthBias*.1; // depth;
		depth *= .5;
		
		outCd.rgb = mix( outCd.rgb, toFogColor, (1.0-outDepth*.1) );
		
//Fog when Player in Powder Snow 
	//}else if( isEyeInWater == 3 ){
		//outCd.rgb = mix( outCd.rgb, toFogColor, (1.0-outDepth*.1) );
		
//Fog when Player in Air
	}else{
	
		// Clear sky Blue = 0xFF = 255/255 = 1.0
		// Rain sky Blue = 0x88 = 136/255 = 0.53333333333
		// Thunder sky Blue = 0x33 = 51/255 = 0.2 = 1.0/(1.0-.2) = 1.25
		skyGreyInf =  (toSkyColor.b-.2)*1.25;
	
		skyGreyCd = vec3(getSkyFogGrey(toSkyColor.rgb));
		//skyGreyCd = mix( skyGreyCd, ((toSkyColor+outCd.rgb*(fogColorBlend*.5+.5))*.5+.5)*toFogColor, skyGreyInf );
		
		vec3 blockBasinCd = outCd.rgb*min(1.0,worldPosYFit*.5+depth+.55);
		
		outCd.rgb = mix( skyGreyCd, blockBasinCd, fogColorBlend );
	}

	
// -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
// -- World Specific Fog & Fresnel Skewing - -- --
// -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

#ifdef NETHER

	float lightInfNether = clamp( max((lightCd.r),biasToOne(lightLumaBase*1.4))
										       - (min(1.0,(.8-depth*.8)+.2))*1., 0.0, 1.0 );
	lightInfNether += lightLumaBase*(depth*.25 +.75);
	
	//lightCd = (lightCd*min(1.0,depth*90.0)+.25*lightLuma);
	vec3 cdLitFog = outCd.rgb * min( vec3(1.0), 1.0-(1.0-lightCd) );
	outCd.rgb = mix( fogColor*.65+skyColor*.35, cdLitFog, lightInfNether );
	outCd.rgb *= mix(vec3(1.0), (fogColor*.5)*(toCamNormalDot*.75+.25), depth*.5);
	float cdNetherBlend = shiftBlackLevels(1.0-depth*.65) - lightLumaBase*.3;
	outCd.rgb = mix( outCd.rgb*(outCd.rgb*.5+.5), outCd.rgb, cdNetherBlend);
	
#else

// Surface Normal Influence
	float dotRainShift = 0.450;//rainStrengthInv*.45;
	
// Block Surface Rolloff
//   Helps with block visibility in the dark
	outCd.rgb *= mix(toFogColor.rgb, vec3(toCamNormalDot*dotRainShift+(.55+dotRainShift)), min(1.0,depth*.5+lightCd.r));
		
#endif



// Add color to glow
	float outCdMin = max(outCd.r, max( outCd.g, outCd.b ) );
	//glowCd = addToGlowPass(glowCd, mix(txCd.rgb,outCd.rgb,.5) * (depth*.8+.2));
	glowCd = addToGlowPass(glowCd, outCd.rgb * (depth*.8+.2));

	glowInf += (max(0.0,luma(outCd.rgb)-.5)*1.85+isLava)*vCdGlow;


#ifdef OVERWORLD
		
// -- -- -- -- -- -- -- -- 
// -- Cold Biome Glow - -- --
// -- -- -- -- -- -- -- -- -- --

// Giving icy biomes a little bit of that ring'ting'dingle'bum

	float frozenSnowGlow = 1.0+(1.0-BiomeTemp)*.3;
	glowCd = addToGlowPass(glowCd, outCd.rgb*frozenSnowGlow*.5*(1.0-sunPhaseMult)*max(0.06,-sunMoonShadowInf)*max(0.0,(1.0-depth*3.0)));

	outCd.rgb *= 1.0+frozenSnowGlow*max(0.06,-sunMoonShadowInf*.1)*rainStrengthInv;//;
    
    
// -- -- -- -- -- -- -- -- -- -- -- 
// Outdoors vs Caving Lighting - -- --
// -- -- -- -- -- -- -- -- -- -- -- -- --

// Brighten blocks when going spelunking
// TODO: Promote control to Shader Options
	float skyBrightMultFit = min(1.0, 1.0-skyBrightness*.1*(1.0-frozenSnowGlow) );
	outCd.rgb *= skyBrightMultFit;
		
	outCd.rgb*=mix(vec3(1.0), lightCd.rgb, min(1.0,  sunPhaseMult*skyBrightness));
	
#endif
	
	glowCd += outCd.rgb*glowInf+(outCd.rgb+.1)*glowInf;

	glowCd = mix(glowCd, vColor.rgb, isLava );

	vec3 glowHSV = rgb2hsv(glowCd);
	glowHSV.z *= glowInf * (depthBias*.6+.5) * GlowBrightness ;

	//outCd.rgb*=1.0+glowHSV.z;


	// -- -- -- -- -- -- -- -- -- -- 
	// -- Lava & Powda Snow Fog - -- --
	// -- -- -- -- -- -- -- -- -- -- -- --
	float lavaSnowFogInf = 1.0-min(1.0, max(0.0,float(isEyeInWater)-1.0) );
	glowHSV.z *= lavaSnowFogInf;
	outCd.rgb = mix( fogColor.rgb, outCd.rgb, lavaSnowFogInf);


// -- -- -- -- -- -- -- -- -- -- -- -- --
// -- Texture Overides from Settings - -- --
// -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

	if( WorldColor ){ // Const; Greyscale colors
		outCd.rgb = luma(vAvgColor.rgb) * vec3(mix(lightCd.r*.9, 1.0, shadowAvg));
		glowHSV.y = 0.0;
		glowHSV.z *= 0.80;
	}
	
	float outEffectGlow = 0.0;
	
	
	// TODO : Dupelicate? Or actually doing something?
	outCd.a*=vAlphaMult;
	
	// Blend Average color with Smart Blur color through plasticity value
	vec3 outCdHSV = rgb2hsv(outCd.rgb);
	vec3 avgCdHSV = rgb2hsv(vAvgColor.rgb);
	outCd.rgb = hsv2rgb( vec3(mix(avgCdHSV.r,outCdHSV.r,vFinalCompare*step(.25,luma(vAvgColor.rgb))), outCdHSV.gb) );
	
// Boost bright colors morso
	boostPeaks(outCd.rgb);
	
   
	vec3 ambientCd = mix( outCd.rgb, vColor.rgb, isLava );
	float ambientGlow = length(ambientCd) * (1.1 + GlowBrightness*.15) * .5;
	ambientGlow = ambientGlow*ambientGlow;
	glowHSV.z = min( glowHSV.z, ambientGlow );// * vCdGlow;
  
	
// -- -- --
	
	
// -- -- -- -- -- -- -- -- -- -- -- -- --
// -- Debugging Views - -- --
// -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

// Debug View - Detail Bluring
//   Display a blending to the texture bluring vertically
#if ( DebugView == 1 )
	outCd.rgb=mix( outCd.rgb, vec3((screenSpace.y/(aspectRatio*.8))*.5+.5), step(abs(screenSpace.x+.75), .05));
	outCd.rgb = mix( outCd.rgb, vec3(1.0,0.0,0.0), step( 0.5, abs(outCd.r-.5)));
	
	//DetailBlurring 0.0-2.0
	float shifter=1.0-(screenSpace.x*.68-.51);
	outCd.rgb = mix( outCd.rgb, vec3(step(shifter, DetailBlurring*.5)), step(0.0,screenSpace.x-0.75)*step(1.15,screenSpace.y));
	
	outCd.rgb=mix( outCd.rgb, vec3(0.0), step(abs(screenSpace.x-0.75), .0012));
	
// Debug View - Shadow Debug
//   Display vertex offsets for where in space they are
//     Sampling the shadow map from
#elif ( DebugView == 3 )
	outCd.rgb=mix(outCd.rgb, vec3(lightCd), step(0.0,screenSpace.x));
#endif


// Debug View - Vanilla vs procPromo
//   Display a side by side view of
//     Default Vanilla next to procPromo
//   (The post processing effects still display tho...)
#if ( DebugView == 4 )
	vec4 debugCd = texture(gcolor, tuv);
	vec4 debugLightCd = texture(lightmap, luv);
	
	float debugBlender = step( .0, screenSpace.x);
	float debugFogInf = min(1.0,depth*2.0);
	
	debugFogInf=clamp(((1.0-gl_FragCoord.w)-.997)*800.0+screenDewarp*.2,0.0,1.0);
	debugCd.rgb = mix( debugCd.rgb, fogColor, debugFogInf);

	//debugCd = debugCd * debugLightCd * vec4(vColor.rgb*(1.0-debugBlender)+(debugBlender),1.0) * vColor.aaaa;
	debugCd = debugCd * debugLightCd * vColor * vColor.aaaa;
	outCd = mix( outCd, debugCd, debugBlender);
#endif

// -- -- --

	//outCd.rgb = vec3((1.0-depthBias));
	
	outDepthGlow = vec4(outDepth, outEffectGlow, 0.0, 1.0);
	outNormal = vec4(vNormal*.5+.5, 1.0);
	// [ Sun/Moon Strength, Light Map, Spectral Glow ]
	outLighting = vec4( lightLumaBase, lightLumaBase, 0.0, 1.0);
	outGlow = vec4( glowHSV, 1.0 );

//}
}


#endif

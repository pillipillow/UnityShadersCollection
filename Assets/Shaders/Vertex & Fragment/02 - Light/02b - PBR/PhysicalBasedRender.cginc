#if !defined(LIGHTING_INCLUDED)
#define LIGHTING_INCLUDED

#include "UnityPBSLighting.cginc"
#include "AutoLight.cginc"

float4 _Colour;
sampler2D _MainTex;
float4 _MainTex_ST;

sampler2D _NormalTex;
float4 _NormalTex_ST;

float _Smoothness;
float _Metallic;
float _BumpScale;

struct appdata
{
	float4 vertex : POSITION;
	float2 tex : TEXCOORD0;
	float3 normal : NORMAL;
	float4 tangent : TANGENT;
};

struct v2f
{
	float4 pos : SV_POSITION;
	float2 uv : TEXCOORD0;
	float3 normal : NORMAL;
	float3 worldPos : TEXCOORD1;
	float4 tangentTex : TEXCOORD2;

	SHADOW_COORDS(5)
};

v2f vert(appdata v)
{
	v2f o;
	o.pos = UnityObjectToClipPos(v.vertex);
	o.uv = v.tex;
	o.normal = UnityObjectToWorldNormal(v.normal);
	o.normal = normalize(o.normal);
	o.worldPos = mul(unity_ObjectToWorld, v.vertex);
	o.tangentTex = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);

	TRANSFER_SHADOW(o);

	return o;
}

//Light
UnityLight CreateLight(v2f i)
{
	UnityLight light;

	#if defined(POINT) || defined(POINT_COOKIE) || defined(SPOT)
		light.dir = normalize(_WorldSpaceLightPos0 - i.worldPos);
	#else
		light.dir = _WorldSpaceLightPos0;
	#endif

	UNITY_LIGHT_ATTENUATION(atten, i, i.worldPos);

	light.color = _LightColor0 * atten;
	light.ndotl = DotClamped(i.normal, light.dir) ; //Lambert equation with saturation clamp
	return light;
}

UnityIndirect CreateIndirectLight(v2f i, float3 viewDir)
{
	UnityIndirect inDirectLight;
	inDirectLight.diffuse = 0;
	inDirectLight.specular = 0;

	#if defined(FORWARD_BASE_PASS)
		inDirectLight.diffuse += float4(max(0, ShadeSH9(float4(i.normal, 1))), 1);
		
		float3 reflectDir = reflect(-viewDir, i.normal);
		Unity_GlossyEnvironmentData envData;
		envData.roughness = 1 - _Smoothness;
		envData.reflUVW = reflectDir;
		inDirectLight.specular = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData);

	#endif

	return inDirectLight;
}

void InitializeFragmentNormal(inout v2f i)
{
	//Normal Map
	float2 normal_uv = TRANSFORM_TEX(i.uv, _NormalTex);
	float3 mainNormal = UnpackScaleNormal(tex2D(_NormalTex, normal_uv), _BumpScale);

	//Tangent Space
	float3 binormal = cross(i.normal, i.tangentTex) * (i.tangentTex.w * unity_WorldTransformParams.w);

	i.normal = normalize(
		mainNormal.x * i.tangentTex +
		mainNormal.y * binormal +
		mainNormal.z * i.normal
	);

	i.normal = normalize(i.normal);
}


fixed4 frag(v2f i) : SV_TARGET
{
	InitializeFragmentNormal(i);

	//Specular
	float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);

	//Texture
	float2 main_uv = TRANSFORM_TEX(i.uv, _MainTex);
	fixed4 albedo = tex2D(_MainTex, main_uv) * _Colour;

	//Metallic
	float3 specularTint; // = albedo * _Metallic;
	float oneMinusReflectivity; // = 1 - _Metallic;
	//albedo *= oneMinusReflectivity;
	albedo = float4(DiffuseAndSpecularFromMetallic(albedo, _Metallic, specularTint, oneMinusReflectivity), 1);

	//From the "UnityPBSLighting.cginc"
	return UNITY_BRDF_PBS //BRDF = bidirectional reflectance distribution function
	(
		albedo, specularTint,
		oneMinusReflectivity, _Smoothness,
		i.normal, viewDir, //Specular
		CreateLight(i), CreateIndirectLight(i, viewDir)
	);
}
#endif
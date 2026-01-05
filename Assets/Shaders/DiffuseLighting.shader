Shader "Custom Lighting/Diffuse Lighting"
{
    Properties
    {
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Opaque"
            "Queue"="Geometry"
        }

        Pass
        {
            Name "ForwardUnlit"
            Tags { "LightMode"="UniversalForward" }

            Cull Back
            ZWrite On
            ZTest LEqual
            Blend One Zero  // Opaque

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma target   4.5

            // URP lighting keywords (no shadows here to keep it simple) - this is a bit of a black art and keeps changing
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _FORWARD_PLUS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float3 positionOS : POSITION;  // object-space vertex position                
                float3 normalOS   : NORMAL;    // object-space vertex normal
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
            };

            static half3 Lambert(half3 N, Light L)
            {
                half nl = saturate(dot(N, L.direction));
                return L.color * nl;
            }

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                float3 positionWS = TransformObjectToWorld(IN.positionOS);
                OUT.positionCS    = TransformWorldToHClip(positionWS);
                OUT.positionWS    = positionWS;
                OUT.normalWS      = TransformObjectToWorldNormal(IN.normalOS);
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                // Normalize just in case (post-interp)
                half3 N = normalize(IN.normalWS);

                // Ambient (flat env color only)
                half3 ambient = unity_AmbientSky.rgb;

                // Main directional light
                Light mainLight = GetMainLight();
                half3 diffuse   = Lambert(N, mainLight);

                // --- Additional lights
                #if defined(_ADDITIONAL_LIGHTS)
                    // Forward+ requires an InputData in scope and the clustered loop macros:
                    InputData inputData = (InputData)0;
                    inputData.positionWS = IN.positionWS;
                    inputData.normalWS   = N;
                    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);

                    // Forward+: non-main directionals (small fixed loop) - this is due to light clustering, I'll explain it in another class
                    #if USE_CLUSTER_LIGHT_LOOP
                    UNITY_LOOP // This does the same as [loop] in most cases, but is more "platform-agnostic"
                    for (uint li = 0; li < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); li++)
                    {
                        Light L = GetAdditionalLight(li, inputData.positionWS, half4(1,1,1,1)); // last parameter is shadowmask, we're not using shadows atm
                        diffuse += Lambert(N, L);
                    }
                    #endif

                    // Forward & Forward+ unified additional light loop - these are lights that aren't clustered
                    uint pixelLightCount = GetAdditionalLightsCount();
                    // The following is a special type of loop - for practical reasons, it's a loop, but in reality it might be or not
                    LIGHT_LOOP_BEGIN(pixelLightCount)
                        Light L = GetAdditionalLight(lightIndex, inputData.positionWS, half4(1,1,1,1));
                        diffuse += Lambert(N, L);
                    LIGHT_LOOP_END
                #endif

                // Just output the parameter color; no lighting.
                return half4(ambient + diffuse, 1);
            }
            ENDHLSL
        }
    }

    Fallback Off
}

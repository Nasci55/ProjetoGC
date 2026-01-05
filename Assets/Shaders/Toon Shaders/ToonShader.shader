Shader "Custom Materials/Toon Shader"
{
    Properties
    {
        [Header(General)]
        [Space]
        _color ("Color", Color) = (1,1,1,1)
        _texture("Texture", 2D) =  "white" {}

        
        
        [Header(Toon Shading)]
        [Space]
        _band0S("First Band Strength", Range(0,1)) = 0.5
        [Space]
        _band1TH("Second Band Treshold", Range(0,1)) = 0.5
        _band1S("Second Band Strength", Range(0,1)) = 0.5
        [Space]
        _band2TH("Third Band Treshold", Range(0,1)) = 0.5
        _band2S("Second Band Strength", Range(0,1)) = 0.5
        

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
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            
            
            float4 _color;
            half _band0S;
            half _band1TH;
            half _band1S;
            half _band2TH;
            half _band2S;
            
            Texture2D _texture;
            SamplerState sampler_texture;
            float4 _texture_ST;

            struct Attributes
            {
                float3 positionOS : POSITION;  // object-space vertex position                
                float3 normalOS   : NORMAL;    // object-space vertex normal
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
                float4 shadowCoord : TEXCOORD3;
             
            };
            

            // Função de iluminação Lambert modificada para Toon Shading com 3 bandas
            static half3 Lambert(half3 N, Light L)
            {
                half nl = saturate(dot(N, L.direction));

                half nlSmooth;
                nlSmooth = _band0S;

                if (nl > _band2TH)
                    nlSmooth = _band2S;
                else if (nl > _band1TH)             
                    nlSmooth = _band1S;


                return L.color * nlSmooth * L.shadowAttenuation;
            }

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                float3 positionWS = TransformObjectToWorld(IN.positionOS);
                OUT.positionCS    = TransformWorldToHClip(positionWS);
                OUT.positionWS    = positionWS;
                OUT.normalWS      = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv            = TRANSFORM_TEX(IN.uv, _texture);
                OUT.shadowCoord   = TransformWorldToShadowCoord(positionWS);
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                // Normalize just in case (post-interp)
                half3 N = normalize(IN.normalWS);

                // Luz ambiente
                half3 ambient = unity_AmbientSky.rgb;


                Light mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));

                half3 toonDiffuse   = Lambert(N, mainLight);

                half4 textureColor = SAMPLE_TEXTURE2D(_texture, sampler_texture, IN.uv);
                
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
                        toonDiffuse += Lambert(N, L);
                    }
                    #endif

                    // Forward & Forward+ unified additional light loop - these are lights that aren't clustered
                    uint pixelLightCount = GetAdditionalLightsCount();
                    // The following is a special type of loop - for practical reasons, it's a loop, but in reality it might be or not
                    LIGHT_LOOP_BEGIN(pixelLightCount)
                        Light L = GetAdditionalLight(lightIndex, inputData.positionWS, half4(1,1,1,1));
                        toonDiffuse += Lambert(N, L);
                    LIGHT_LOOP_END
                #endif

                return half4((ambient + toonDiffuse ) * _color.rgb * textureColor.rgb, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            Cull Back
            ZWrite On
            ZTest LEqual
            ColorMask 0
            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag

            // URP includes
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float _Speed;
            float _Strength;

            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings vert (Attributes v)
            {
                Varyings o;

                float3 posWS = TransformObjectToWorld(v.positionOS);
                // Transform world position to shadow clip space
                o.positionCS = TransformWorldToHClip(posWS);

                return o;
            }

            half4 frag (Varyings i) : SV_Target
            {
                return 0;
            }

            ENDHLSL
        }
    }
    Fallback Off
}

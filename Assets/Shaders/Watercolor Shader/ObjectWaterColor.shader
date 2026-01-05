Shader "Custom Materials/Water Color"
{
    Properties
    {
        _texture("Texture", 2D) =  "white" {}
        _strenght("Edge Strenght", float) = 1
        [Space]
        _edgeMaskMin("Interior Radius", Range(0,1)) = 0.5
        _edgeInteriorLight("Interior Lightness", float) = 0.7
        [Space]
        _edgeMaskMax("Outside Radius", Range(0,1)) = 0.5
        _edgeDarken("Edge Darkness", float) = 0.2
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


            Texture2D _texture;
            SamplerState sampler_texture;
            float4 _texture_ST;
            float4 _texture_TexelSize;


            float _edgeMaskMin;
            float _edgeMaskMax;
            float _edgeDarken;
            float _edgeInteriorLight;
            float _strenght;

            struct Attributes
            {
                float3 positionOS : POSITION;              
                float3 normalOS   : NORMAL;     
                float2 uv         : TEXCOORD0;   
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float3 positionOS : TEXCOORD2;
                float2 uv         : TEXCOORD3;
                float4 shadowCoord : TEXCOORD4;
            };

            // combina a atenuação da distância, da sombra e da cor da luz
            static half3 LightCalculation( Light L, half3 shadowColor)
            {
                return  L.shadowAttenuation * L.distanceAttenuation * L.color + shadowColor * (1.0 - L.shadowAttenuation);
            }

            // tira samples das cores dos 9 pixeis à volta e devolve a diferença entre 
            // eles, desta maneira é possivel observar quando há uma mudança de cor na textura fazendo uma edge
            float GetColorEdges(float2 uv)
            {
                  // Tamanho do texel multiplicado pela intensidade caso se queira uma área maior de samples
                  float2 texel = _texture_TexelSize.xy * _strenght;

                float3 tr = SAMPLE_TEXTURE2D(_texture, sampler_texture, uv + texel * float2( 1,  1)).rgb;
                float3 t = SAMPLE_TEXTURE2D(_texture, sampler_texture, uv + texel * float2( 0,  1)).rgb;
                float3 tl = SAMPLE_TEXTURE2D(_texture, sampler_texture, uv + texel * float2(-1,  1)).rgb;
                float3 l = SAMPLE_TEXTURE2D(_texture, sampler_texture, uv + texel * float2(-1, 0)).rgb;
                float3 bl = SAMPLE_TEXTURE2D(_texture, sampler_texture, uv + texel * float2(-1, -1)).rgb;
                float3 b = SAMPLE_TEXTURE2D(_texture, sampler_texture, uv + texel * float2(0, -1)).rgb;
                float3 br = SAMPLE_TEXTURE2D(_texture, sampler_texture, uv + texel * float2( 1, -1)).rgb;
                float3 r = SAMPLE_TEXTURE2D(_texture, sampler_texture, uv + texel * float2( 1, 0)).rgb;

                float bottomRight = r + b + br;
                float bottomLeft  = l + b + bl;
                float topLeft     = l + t + tl;
                float topRight    = r + t + tr;

                // Cálculo da intensidade da borda pela diferença de cores, utilizei os dois para experimentar qual ficava melhor
                // edgeTex faz apenas a diferença dos cantos diagonais
                float edgeTex = length(tr - bl) + length(br - tl);
                
                // edgeTexBigger faz a diferença dos cantos diagonais e dos lados
                float edgeTexBigger = length(topRight - bottomLeft) + length(topRight - topLeft);

                // return edgeTex;
                return edgeTexBigger;
            }

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                float3 positionWS = TransformObjectToWorld(IN.positionOS);
                OUT.positionCS    = TransformWorldToHClip(positionWS);
                OUT.positionWS    = positionWS;
                OUT.normalWS      = TransformObjectToWorldNormal(IN.normalOS);
                OUT.positionOS    = IN.positionOS;
                OUT.uv            = TRANSFORM_TEX(IN.uv, _texture);
                OUT.shadowCoord = TransformWorldToShadowCoord(positionWS);

                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                // Normalize just in case (post-interp)
                half3 N = normalize(IN.normalWS);
                // Direção da câmera
                half3 viewDirection = normalize(GetWorldSpaceViewDir(IN.positionWS));
                
                // Máscara baseada no ângulo entre normal e câmera
                half edge = 1 - saturate(dot(N, viewDirection));
                
                // Suaviza a transição da edge que pode ser selecionada pelo utilizador
                half edgeMask = smoothstep(_edgeMaskMin, _edgeMaskMax, edge);

                // Sample da textura escolhida pelo utilizador
                half4 textureColor = SAMPLE_TEXTURE2D(_texture, sampler_texture, IN.uv);

                 // Luz ambiente global
                half3 ambient = unity_AmbientSky.rgb;
                
                // Cor interna e das bordas para fazer o efeito de aguarela, mais escuro nas bordas e mais claro no interior
                half3 innerColor = textureColor.rgb * _edgeInteriorLight; 
                half3 edgeColor  = textureColor.rgb * _edgeDarken;


                // Detecção de edges pela cor
                float edgeTex = GetColorEdges(IN.uv);

                // Combina as edges das cores com as edges com base no angulo da camera
                half finalEdge = saturate(max(edgeMask, edgeTex));


                //Mistura as cores de dentro com as cores de fora com base na edge final 
                half3 watercolor = lerp(innerColor, edgeColor, finalEdge);

                // Cor do prórpio objeto usado nas sombras
                half3 shadowTint = watercolor * 0.7;



                // Obtem as coordenadas de sombra
                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);


                // Luz principal
                Light mainLight = GetMainLight(shadowCoord);
                
                // Cálculo da luz principal com a cor da sombra
                half3 lightCalc   = LightCalculation(mainLight, shadowTint) ;

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
                        lightCalc += LightCalculation(L, shadowTint);
                    }
                    #endif

                    // Forward & Forward+ unified additional light loop - these are lights that aren't clustered
                    uint pixelLightCount = GetAdditionalLightsCount();
                    // The following is a special type of loop - for practical reasons, it's a loop, but in reality it might be or not
                    LIGHT_LOOP_BEGIN(pixelLightCount)
                        Light L = GetAdditionalLight(lightIndex, inputData.positionWS, half4(1,1,1,1));
                        lightCalc += LightCalculation(L, shadowTint);
                    LIGHT_LOOP_END
                #endif
                // Just output the parameter color; no lighting.
                return half4((ambient + lightCalc) * watercolor, 1);
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

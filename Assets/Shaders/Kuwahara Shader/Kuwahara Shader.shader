Shader "Kuwahara Effect"
{
    Properties
    {
        _strenght ("Strenght", Float) = 1
        _texture ("Paper Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Transparent"
        }

        ZWrite Off
        ZTest Always
        Cull Off
        Blend One Zero

        Pass
        {
            Name "Kuwahara Effect"

            HLSLPROGRAM
            // Entry points provided by Blit.hlsl
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // Provides Varyings, Attributes, Varyings_BlitTexure, etc.
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _strenght;

            Texture2D _texture;
            SamplerState sampler_texture;
            float4 _texture_ST;


            // Color from Full Screen Pass (because "Fetch Color Buffer" is enabled)
            SAMPLER(sampler_BlitTexture);

            // Camera depth (because you required Depth in the feature)
            TEXTURE2D_X(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);

            // Obter a média dos pixeis à volta do pixel que está a ser testado podendo serem utilizados N numero de samples
            // Por exemplo obter a média dos pixeis que se encontram no canto superior direito do pixel original
            float3 GetAverage(float2 uvStart, int n)
            {
                float3 sum = 0;
                float count = 0;

                for(int y = 0; y <= n; y++)
                {
                    for(int x = 0; x <= n; x++)
                    {
                        float2 uv = uvStart + float2(x, y) * _BlitTexture_TexelSize.xy;
                        float3 c = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv).rgb;
                        sum += c;
                        count++;
                    }
                }

                return sum / count;
            }


            //Obter a variância entre a média de um dos pixeis selecionados e o pixel original com um numero N de samples 
            //que se queira retirar
            float GetVariance(float2 uvStart, int n, float3 average)
            {
                float sum = 0;
                float count = 0;

                for(int y = 0; y <= n; y++)
                {
                    for(int x = 0; x <= n; x++)
                    {
                        float2 uv = uvStart + float2(x, y) * _BlitTexture_TexelSize.xy;
                        float3 c = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv).rgb;

                        float i = (c.r + c.g + c.b) / 3.0;
                        float m = (average.r + average.g + average.b) / 3.0;

                        float d = i - m;
                        sum += d * d;

                        count++;
                    }
                }

                return sum / count;
            }

            //Pegar em 4 samples e aplicar as funções a cima. Após isso observar qual das 4 samples tem a 
            //melhor variancia para o UV em questão
            float4 Kuwahara(float2 uv)
            {
                int n = (int)_strenght;

                float2 TL = uv + _BlitTexture_TexelSize.xy * float2(-n,  -n);
                float2 TR = uv + _BlitTexture_TexelSize.xy * float2( 0,  -n);
                float2 BL = uv + _BlitTexture_TexelSize.xy * float2(-n,  0);
                float2 BR = uv + _BlitTexture_TexelSize.xy * float2( 0,  0);

                float3 average0 = GetAverage(TL, n);
                float3 average1 = GetAverage(TR, n);
                float3 average2 = GetAverage(BL, n);
                float3 average3 = GetAverage(BR, n);

                float variance0 = GetVariance(TL, n, average0);
                float variance1 = GetVariance(TR, n, average1);
                float variance2 = GetVariance(BL, n, average2);
                float variance3 = GetVariance(BR, n, average3);

                float3 best = average0;
                float bestV = variance0;

                if(variance1 < bestV)
                { 
                    bestV = variance1; 
                    best = average1; 
                }
                if(variance2 < bestV)
                { 
                    bestV = variance2; 
                    best = average2; 
                }
                if(variance3 < bestV)
                { 
                    bestV = variance3; 
                    best = average3; 
                }

                return float4(best, 1);
            }


            half4 Frag (Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float2 uv = input.texcoord;

                float2 paperUV = TRANSFORM_TEX(uv, _texture);
                float3 paper = _texture.Sample(sampler_texture, paperUV).rgb;

                float4 kuwahara = Kuwahara(uv);

                // Sample original color from _BlitTexture
                half4 col = SAMPLE_TEXTURE2D_X(
                    _BlitTexture,
                    sampler_BlitTexture,
                    uv
                );
                // 0.4 é apenas um numero mágico para que o efeito fique ligeiramente mais claro
                float3 finalColor = (kuwahara.rgb * paper) / 0.4;
                
                return float4(finalColor, 1);
            }

            ENDHLSL
        }
    }
}
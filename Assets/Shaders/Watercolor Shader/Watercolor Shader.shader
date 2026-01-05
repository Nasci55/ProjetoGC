Shader "Custom Renderers/WaterColor Effect"
{
    Properties
    {
        _texture ("Paper Texture", 2D) = "white" {}

        [Space]
        _sampleEdgesRadius ("Strenght", Float) = 1
        _blurRadius("Outline Strenght", float) = 1
        [Space]
        _edgesSensMin ("Outline Sensibility Min", Range(0,1)) = 0.2
        _edgesSensMax ("Outline Sensibility Max", Range(0,1)) = 0.2
        [Space]
        _colorIntensityEdges ("Color Intensity Edges", Range(0,10)) = 1


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
            Name "Watercolor Effect"

            HLSLPROGRAM
            // Entry points provided by Blit.hlsl
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // Provides Varyings, Attributes, Varyings_BlitTexure, etc.
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"


            float _sampleEdgesRadius;

            Texture2D _texture;
            SamplerState sampler_texture;
            float4 _texture_ST;
            float _edgesSensMin;
            float _edgesSensMax;
            float _colorIntensityEdges;
            float _blurRadius;
            


            // Color from Full Screen Pass (because "Fetch Color Buffer" is enabled)
            SAMPLER(sampler_BlitTexture);

            // Função que calcula edges com as diferenças na depth texture
            // Sample dos 8 vizinhos à volta do pixel atual
            // Não é utilizado neste momento mas deixei caso fosse necessário voltar a utilizar
			float GetEdges(float2 uv)
			{
                // Tamanho do texel multiplicado pela intensidade caso se queira uma área maior de samples
				float2 offset = _sampleEdgesRadius * _CameraDepthTexture_TexelSize.xy;

				float2 uvTopRight    = uv + float2( 1,  1) * offset;
                float2 uvRight       = uv + float2( 1,  0) * offset;
				float2 uvBottomRight = uv + float2( 1, -1) * offset;
                float2 uvBottom      = uv + float2( 0,  1) * offset;
				float2 uvBottomLeft  = uv + float2(-1, -1) * offset;
                float2 uvLeft        = uv + float2( -1,  0) * offset;
				float2 uvTopLeft     = uv + float2(-1,  1) * offset;
                float2 uvTop         = uv + float2( 0,  1) * offset;

				float dTR = SampleSceneDepth(uvTopRight);
                float dR  = SampleSceneDepth(uvRight);
				float dBR = SampleSceneDepth(uvBottomRight);
                float dB  = SampleSceneDepth(uvBottom);
				float dBL = SampleSceneDepth(uvBottomLeft);
                float dL  = SampleSceneDepth(uvLeft);
				float dTL = SampleSceneDepth(uvTopLeft);
                float dT  = SampleSceneDepth(uvTop);

                float bottomRight = dR + dB + dBR;
                float bottomLeft  = dL + dB + dBL;
                float topLeft     = dL + dT + dTL;
                float topRight    = dR + dT + dTR;

				// float GX = dTR - dBL;
				// float GY = dBR - dTL;

				float GX = topRight - bottomLeft;
                float GY = bottomRight - topLeft;

				float G = abs(GX) + abs(GY); 

				return G;	
			}

        
            // Função que calcula edges usando diferenças na cor
            float GetColorEdges(float2 uv)
            {
                float2 t = _BlitTexture_TexelSize.xy * _sampleEdgesRadius;
            
                float uvTopRight  =  (float)SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uv + float2( 1, 1) * t);
                float uvTopLeft  =  (float)SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture,uv + float2(-1, 1)* t);
                float uvBottomLeft  =  (float)SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture,uv + float2(-1,  -1)* t);
                float uvBottomRight  =  (float)SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture,uv + float2(1, -1)* t);
                

                float edge = abs(uvTopRight - uvBottomLeft) + abs(uvBottomRight - uvTopLeft);
                return edge;
            }
            
            // Aplica um blur às edges utilizando o GetColorEdges
            float BlurEdgeMask(float2 uv)
            {
                float2 t = _BlitTexture_TexelSize.xy * _blurRadius ;

                float e = 0;
                e += GetColorEdges(uv + t * float2(-1, 0));
                e += GetColorEdges(uv + t * float2( 1, 0));
                e += GetColorEdges(uv + t * float2( 0,-1));
                e += GetColorEdges(uv + t * float2( 0, 1));

                return e;
            }


            half4 Frag (Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float2 uv = input.texcoord;


                half2 paperUV = TRANSFORM_TEX(uv, _texture);
                half3 paper = _texture.Sample(sampler_texture, paperUV).rgb;


                // Sample original color from _BlitTexture
                half4 col = SAMPLE_TEXTURE2D_X(
                    _BlitTexture,
                    sampler_BlitTexture,
                    uv
                );
                // Inverte as cores para CMY para poder serem feitos cálculos de cor mais fielmente ao que seria na vida real
                col.rgb = 1 - col.rgb;
    

                float blurMask= BlurEdgeMask(uv);

                
                float edge = saturate(blurMask);

                // calcula a cor das edges com base na cor da textura já existente e a definida pelo utilizador
                half3 edgeColor = col.rgb * _colorIntensityEdges;

                
                half3 finalColor = lerp(col.rgb, edgeColor, edge);

                //volta a inverter as cores para RGB
                finalColor = 1 - finalColor.rgb;
                // Aplica a textura de papel
                finalColor *= (paper);
                return half4(finalColor, 1);
            }
            ENDHLSL
        }
    }
}
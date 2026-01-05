Shader "Custom Renderers/Outline Shader"
{
	Properties
	{
		_outlineColor("Outline color", Color) = (1,1,1,1)
		_strenght ("Outline Strength", float) = 1

		_sensibility("Outline Sensibility", Range(0,1)) = 0.5
		_thickness("Outline Thickness", float) = 1

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
			Name "OutlineS"
			HLSLPROGRAM
			// Entry points provided by Blit.hlsl
			#pragma vertex Vert
			#pragma fragment Frag

			float4 _outlineColor;
			float _strenght;
			float _sensibility;
			float _thickness;

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

			// Provides Vert(), Attributes, Varyings, _BlitTexture, etc.
			#include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"


			SAMPLER(sampler_BlitTexture);

			// Função que calcula edges com as diferenças na depth texture usando Roberts Cross Operator
			float GetEdges(float2 uv)
			{
				float2 offset = _thickness * _CameraDepthTexture_TexelSize.xy;

				float2 uvTopRight    = uv + float2( 1,  1) * offset;
				float2 uvBottomRight = uv + float2( 1, -1) * offset;
				float2 uvBottomLeft  = uv + float2(-1, -1) * offset;
				float2 uvTopLeft     = uv + float2(-1,  1) * offset;

				// Amostras da depth texture
				float dC  = SampleSceneDepth(uv);
				float dTR = SampleSceneDepth(uvTopRight);
				float dBL = SampleSceneDepth(uvBottomLeft);
				float dBR = SampleSceneDepth(uvBottomRight);
				float dTL = SampleSceneDepth(uvTopLeft);
				
				// Converte profundidade para espaço linear [0–1]
				float ldC  = Linear01Depth(dC, _ZBufferParams);
				float ldTR = Linear01Depth(dTR, _ZBufferParams);
    			float ldBR = Linear01Depth(dBR, _ZBufferParams);
    			float ldBL = Linear01Depth(dBL, _ZBufferParams);
    			float ldTL = Linear01Depth(dTL, _ZBufferParams);

				float GX = ldTR - ldBL;
    			float GY = ldBR - ldTL;
				

				// Reduz o efeito em objetos distantes
				float depthFactor = saturate(1.0 - ldC);

				float G = abs(GX) + abs(GY); 

				return G* depthFactor;	
			}

			half4 Frag (Varyings input) : SV_Target
			{
				UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
				float2 uv = input.texcoord;


				// Sample original color from _BlitTexture
				half4 col = SAMPLE_TEXTURE2D_X(
					_BlitTexture,
					sampler_BlitTexture,
					uv
				);


				float edge = GetEdges(uv);
				edge = saturate(edge * _strenght);
				


				float centerDepth = Linear01Depth(SampleSceneDepth(uv), _ZBufferParams);


				// Ajusta a sensibilidade com base na distância
				// Objetos distantes ficam mais sensíveis ao outline
				float depthScaledSens = lerp(_sensibility, 1.0, centerDepth);
				
				// Suaviza o threshold do outline
				edge = smoothstep(depthScaledSens,depthScaledSens + 0.01, edge);

				half3 outline = _outlineColor.rgb * edge; 
				half4 returnValue = lerp(col, half4(outline, 1), edge);
				return returnValue;
			}
			ENDHLSL
		}
	}
}
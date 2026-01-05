# Relatório Computação Gráfica / Licenças

Trabalho feito por: 
- Gonçalo Nascimento a22402299


# Aviso prévio
Devido a um erro com o git lfs as scenes dentro do projeto não correspondem com as das imagens demonstradas neste relatório.


# Toon Shader
Para este shader utilizei como base o shader dado pelo professor durante as aulas.
## Cel Shading
Inicialmente optei por fazer a parte do cel shading primeiro. 
Para atingir este efeito adaptei o cálculo "Lambertiano" para que fizesse um smoothstep[^1] usando o produto escalar das normais com a luz. 
Desta maneira alcancei o objetivo pretentido com o cel shading, podendo alterar os valores no editor.
![[Pasted image 20251224045242.png]]
Após isso adicionei suporte para texturas
![[Pasted image 20251227002440.png]]
Depois de adicionar o suporte para texturas notei que toon shader apenas com 2 bands não era ideal, então adicionei uma band intermediária retirando o smoothstep adiconado previamente e fazendo uma lógica com um sistema de if's.
![[Pasted image 20251230105519.png]]
## Outline
Inicialmente o outline iria ser feito com edge detection. O cálculo usado será o de Roberts cross.
Este efeito terá que ser feito pelo camera renderer e terá como base o script dado pelo professor no TPC 6.
Para fazer o edge detection comecei por fazer uma função em que pegava uma coordenada de uv da depth texture e verificava ao seu redor a diferença entre os tons de cinzento, caso a diferença seja maior do que pretendido desenha uma edge, se não for, ignora e não desenha nada.  O site de onde os meus cálculos foram baseados podem ser encontrados nesta referência[^2] .
### Métodos utilizados
Inicialmente ao fazer Roberts cross, comecei por fazer sample dos 4 pixéis à volta do pixel sampled. Esta minha primeira abordagem teve um erro crucial que impedia correr o programa.
Esta era:
```HLSL
float2 uvTopRight = uv + float2(1,1);

float2 uvBottomRight = uv + float2(1,-1);

float2 uvBottomLeft = uv + float2(-1,-1);

float2 uvTopLeft = uv + float2(-1,1);
```
Estava a adicionar um valor inteiro, algo que não faz sentido pois mapas de UVs sendo de 0 a 1 este resultado nunca estaria correto. Rapidamente alterei o cálculo de modo a que apanhasse mesmo o pixel à volta e para alcançar esse efeito utilizei:
```HLSL
float2 uvTopRight = uv + float2(1,1)* _CameraDepthTexture_TexelSize.xy;

float2 uvBottomRight = uv + float2(1,-1)* _CameraDepthTexture_TexelSize.xy;

float2 uvBottomLeft = uv + float2(-1,-1)* _CameraDepthTexture_TexelSize.xy;

float2 uvTopLeft = uv + float2(-1,1)* _CameraDepthTexture_TexelSize.xy;
```
O restante da função estava:
```HLSL
float uvCoordinateTopRight = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uvTopRight);

float uvCoordinateBottomRight = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uvBottomRight);

float uvCoordinateBottomLeft = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uvBottomLeft);

float uvCoordinateTopLeft = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uvTopLeft);
 
float GX = uvCoordinateTopRight - uvCoordinateBottomLeft;
float GY = uvCoordinateBottomRight - uvCoordinateTopLeft;

  
float G = abs(GX) + abs(GY);
```

Ao retornar a função e usá-la como retorno do shader o ecrã estava totalmente branco. Experimentei retornar apenas a profundidade e a imagem apresentada parecia-me correta, por este motivo deduzi que o erro era com a minha conta. Após algumas tentativas e mudar algumas partes do código percebi que o "Sample_Depth_Texture" não estava correto e troquei por "SampleSceneDepth"
A partir deste momento consegui observar as outlines nos objetos, mas apenas aqueles com materiais default do unity, os objetos que tinham o meu toon shader não eram visiveis. Indo ao frame debugger pude observar que de facto o meu toon shader não aparecia na fase de "DrawDepthNormalPrepass", ou seja assumi que o problema estava no meu toon shader.
Após pesquisar um pouco reparei que o problema estava em como eu estava a fazer o meu renderer, o facto de estar a utilizar Screen Space Ambient Oclusion e isso alterava a maneira em como os materiais eram passados para o depth map, para resolver este problema decidi retirar o SSAO, neste momento ainda não fazia sentido ter.
Em seguida adicionei parâmetros para ajustar a cor do outline, adicionei também um parâmetro para ajustar a grossura na linha diretamente no cálculo dos outlines e um elemento de strength.

Adicionei também um cálculo para suavizar o efeito com a distância, pegando no no pixel central e vendo se ele estava no limite que a edge texture apanhava.

Adicionei suporte para sombras e luzes mas como foi feito a seguir ao shader seguinte acabei por copiar um pouco a mesma lógica. 
No final o efeito ficou:
![[Pasted image 20260105224901.png]]


--------------------------------------------------------------------------

# WaterColor Shader
Para fazer o watercolor shader irei utilizar novamente camera renderer e utilizar mais uma vez, como base, o script do professor. Irei fazer este shader utilizando o filtro Kuwahara[^3] visto que este aplica um filtro de blur e simultaneamente preserva as edges.
Primeiramente tirei samples dos pixeis das diagonais, tirei um sample da textura e aqui acabei por fazer dois cálculos diferentes. Inicialmente ao estudar o efeito entendi que o objetivo era ficar com o sample com menos diferenciação de cor então inicialmente foi o que eu fiz:
![[Pasted image 20251231012107.png]]
Após isso experimentei um cálculo diferente, invés de ir buscar apenas o valor que tem menos diferenciação, acabei por fazer uma média de todos os pixeis que deu este resultado:
![[Pasted image 20251231012440.png]]

Atualmente o código é :
``` HLSL
float4 KuwaharaEffect(float2 uv)
{

float2 strenght = _BlitTexture_TexelSize.xy * _strenght;

  
float2 uvTopRight    = uv + float2( 1,  1) * strenght;
float2 uvBottomRight = uv + float2( 1, -1) * strenght;
float2 uvBottomLeft  = uv + float2(-1, -1) * strenght;
float2 uvTopLeft     = uv + float2(-1,  1) * strenght;


float4 tr = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uvTopRight);
float4 br = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uvBottomRight);
float4 tl = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uvTopLeft);
float4 bl = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_BlitTexture, uvBottomLeft);

float trValue = (tr.r + tr.g + tr.b)/3;
float brValue = (br.r + br.g + br.b)/3;
float tlValue = (tl.r + tl.g + tl.b)/3;
float blValue = (bl.r + bl.g + bl.b)/3;

  
  

float4 samplesRGB[4] =
{
	tr,
	br,
	tl,
	bl
};

  
float samples[4] =
{
	trValue,
	brValue,
	tlValue,
	blValue
};


float minVariance = samples[0];
float4 minColor = samplesRGB[0];

for(int i = 0; i < 4; i++)
{

	if(samples[i] < minVariance)
	{
		minVariance = samples[i];
		minColor = samplesRGB[i];
	}

}

if(_teste > 0.5)
return (tr + br + tl + bl)/ 4;  
else
return minColor;

}
```

Ao comparar com outras imagens que utilizavam o efeito Kuwahara os resultados que eu estava a obter não se assemelhavam, então tentei procurar pelo artigo original, mas este estava protegido e não era de fácil acesso, por isso os meus próximos cálculos seram com base no artigo"Adaptative Kuwahara filter" por Krzysztof Bartyzel [^4] 
De acordo com o artigo, Kuwahara Effect precisa de 3 coisas para ser calculado:
Sample de 4 áreas
A média de cada áreas
A variância de cada área

Inicialmente estava a fazer estes 3 cálculos simultaneamente e estavam-me a dar alguns erros, separei todas as contas onde numa dessas fazia o cálculo da média, noutra a variância e noutra juntava as duas e calculava as 4 samples.
Esta era apenas o primeiro objetivo, fazer a imagem parecer um pintura. Em seguida vou adicionar uma textura de papel por cima.
Após adicionar a textura de papel adicionei também algum noise nas cores, pois após analisar alguns quadros as cores nunca estão completamente homogéneas, há sempre algumas variações de cor.
Experimentei um value noise, mas a imagem parecia suja então acabei por procurar outro tipo de noises mas nenhum ficava bem.

Ao explorar um pouco mais imagens de desenhos apercebi-me que o efeito Kuwahara não era o que eu queria. Um dos grandes objetivo do Kuwahara é um blur que preserve as edges, em pintura aguarelas não é de todo isso que se quer. Acabei por deixar o efeito Kuwahara no projeto até porque acho que fica um efeito interessante, mas para uma pintura sem ser aguarela.
Mesmo assim fica aqui o efeito final:
![[Pasted image 20260105225042.png]]

Após ter recomeçado deparei-me com o seguinte video  "Turn 3D into watercolor magic: step-by-step shader tutorial"[^5] que serviu como base/passos do que eu teria que fazer para alcançar o Watercolor shader.

A minha primeira ideia para adicionar o blur nas edges e o centro ser mais claro foi fazer um edge detection com base na depth texture. Reutilizei o edge detection que tinha utilizado no outline shader, mas acrescentei mais samples, invés de ser apenas nas diagonais adicionei nos lados, em cima e em baixo mas o efeito não me pareceu mudar pelo menos do que eu reparei. 
Após ter feito o edge detection fiz também um box blur para ser apenas aplicado onde existe edge detection. Primeiro fiz uma mask do outline, e depois multipliquei pelo blur.
Após ter a edge detection com o blur comecei a tentar fazer smoothsteps para escurecer as edges e meter o centro mais esbranquiçado. 
Sem ter grandes resultados acabei por me focar apenas nas edges da imagem, troquei o box blur e fiz diretamente um blur com as edges:
```c#
float BlurEdgeMask(float2 uv)
{

	float2 t = _BlitTexture_TexelSize.xy * 3.0;  

	float e = 0;

	e += GetEdges(uv + t * float2(-1, 0));
	e += GetEdges(uv + t * float2( 1, 0));
	e += GetEdges(uv + t * float2( 0,-1));
	e += GetEdges(uv + t * float2( 0, 1));

	return e;
}
```

Subtraindo esta mask à imagem original foi possível começar a observar o blend de cores que é pretendido com um watercolor effect:

Scene Mode:
![[Pasted image 20260103153205.png]]

Game Mode:
![[Pasted image 20260103153231.png]]

O outline escuro estava demasiado proeminente e ainda não estava irregular como era suposto. 
Após algumas tentativas falhadas de aplicar tipos de noise utilizando uma função com senos e de atenuar o outline acabei por perceber que não fazia grande sentido estar a utilizar outlines com base na profundidade, o meu objetivo neste caso é notar variações de cor, como se o artista tivesse a pintar com cores diferentes a tela, ou seja passei a utlizar um outline que deteta variações de cor e não de diferenças de profundidade.
Outra alteração que fiz foi passar todos o espaço em que estou a trabalhar para CMY invés de RGB e passei a fazer somas e subtrações de cores dentro do espaço CMY, mas também não foi exatamente o que eu precisava.
Até este momento a fazer o watercolor shader acabei por ignorar muito o material dos objetos, julguei que era um efeito que era totalmente feito num Full Screen Pass Renderer, mas após ver outras maneiras de como algumas pessoas estavam a fazer este tipo de shader percebi que os materiais dos objetos são extremamente essenciais para a realização deste shader, então comecei a focar-me nos materiais dos objetos em si. 

Para começar a fazer o shader do material comecei por tentar fazer o material parecer-se um pouco com esta imagem:
![[Pasted image 20260104170327.png]]
Ou seja nas edges ficar mais escuro e no centro mais claro, pensei que isto com o Screen Renderer iria funcionar bem.

Primeiramente utilizei as normais do objeto mais a posição da camera para determinar as partes que estavam viradas para a camera e a partir dai criei :
![[Pasted image 20260104175428.png]]
Após isso adicionei suporte para texturas e fiz com que a cor central fosse a cor da textura e a cor das edges serem uma variante mais escura da cor da textura:
![[Pasted image 20260104185620.png]]

Após ter feito isto decidi aumentar muito mais a claridade de todos os objetos visto que não há propriamente partes escuras em aguarelas. Outra alteração que fiz foi adicionar o mesmo processo de sample de cores que tinha feito no screen renderer, deste modo seria ainda mais visivel as "manchas" que as aguarelas fazem:

Scene Mode s/Samples de cor
![[Pasted image 20260104201901.png]]

Scene Mode c/ Samples de cor
![[Pasted image 20260104202248.png]]


Game Mode s/ Samples de cor
![[Pasted image 20260104205624.png]]



Game Mode c/Samples de cor
![[Pasted image 20260104202334.png]]


O efeito não é super evidente mas para mim ficava ligeiramente melhor.
Em seguida comecei a adicionar suporte para sombras, usei como base um dos TPCs feitos para a UC. 
Após aplicar a funcionalidade para os objetos darem "cast" a sombra implementei também a funcionalidade destes receberem:
![[Pasted image 20260105005724.png]]
Inicialmente parecia funcionar mas quando mexia a camera no editor criava artefactos nas meshes como por exemplo:
![[Pasted image 20260105005945.png]]

Inicialmente pensei que pudesse ser de Shadow Cascades porque notava-se uma mudança quando passava pelos objetos, mas visto que os objetos com o material default do unity não tinham este efeito rapidamente descartei esta hipótese.
Ao rever uma das aulas do semestre reparei que era a maneira em como estava a passar a sombra para a Main Light, resolvendo assim a situação. 
Adicionei às sombras a cor do próprio objeto para tentar fazer com que parecesse um blend de cores mas não tive bem esse resultado, acabou por ficar um pouco estranho:
![[Pasted image 20260105074747.png]]
No processo acabei por retirar totalmente a função de Lambert.

Após ter feito isto adicionei também suporte para múltiplas luzes e logo em seguida para luzes baked. Inicialmente não encontrei informações sobre implementação de luzes baked para shaders custom, então procurei nos packages do unity e encontrei dentro do GlobalIllumination, Lighting e ImageBasedRendering e após procurar alguma das funções que econtrei dentro dos ficheiros deparei-me com a seguinte thread  using light probes in a custom vert / frag shader[^8] onde recomendam usar a função SampleSH.
Infelizmente apenas consegui implementar suporte para luzes extra mas que não estejam baked.
Sendo este o resultado final do watercolor shader:
![[Pasted image 20260105223918.png]]

# Cross Hatching Shader
Infelizmente devido a ter passado bastante tempo no watercolor shader acabei por não ter tempo para fazer o efeito de Cross Hatching.


# Licenças 
"POLYGON - Horror Carnival" made by Synty Store under the license of:
"[One Time Purchase Licence](https://syntystore.com/pages/one-time-purchase-licence)"


"Texture Labs Paper304 - Bright Clean Heavy Paper"  under the license of:
[FREE FOR COMMERCIAL USE](https://texturelabs.org/terms)

# Referências
https://www.youtube.com/watch?v=I6HVbfMx2s4
https://www.scratchapixel.com/lessons/3d-basic-rendering/phong-shader-BRDF/phong-illumination-models-brdf.html
https://www.wayline.io/blog/cel-shading-a-comprehensive-expert-guide
https://thebookofshaders.com
https://homepages.inf.ed.ac.uk/rbf/HIPR2/roberts.htm
https://www.youtube.com/watch?v=5EuYKEvugLU
https://www.youtube.com/watch?v=uihBwtPIBxM
https://grokipedia.com/page/Roberts_cross#algorithm-procedure
https://ameye.dev/notes/edge-detection-outlines/
https://www.youtube.com/watch?v=Md8l_GK9Sfg
https://gfx.cs.princeton.edu/gfx/pubs/Lu_2010_IPS/lu_2010_ips.pdf
https://reference.wolfram.com/language/ref/KuwaharaFilter.html
https://link.springer.com/article/10.1007/s11760-015-0791-3
https://www.youtube.com/watch?v=5xUT5QdkPAU
https://cyangamedev.wordpress.com/2020/10/06/watercolour-shader-experiments/
https://docs.unity3d.com/6000.0/Documentation/Manual/urp/use-built-in-shader-methods-additional-lights-fplus.html

# Footnotes

[^1]: https://www.youtube.com/watch?v=I6HVbfMx2s4

[^2]: https://grokipedia.com/page/Roberts_cross#algorithm-procedure

[^3]: https://youtu.be/LDhN-JK3U9g?si=263bchKziU6wqDrz

[^4]: Bartyzel, K. Adaptive Kuwahara filter. _SIViP_ **10**, 663–670 (2016). https://doi.org/10.1007/s11760-015-0791-3

[^5]: https://youtu.be/YMp7VaXuB5A?si=skATa2B7kWcGwhqY

[^6]: https://www.youtube.com/watch?v=5xUT5QdkPAU

[^7]: https://docs.unity3d.com/6000.0/Documentation/Manual/built-in-shader-examples-receive-shadows.html

[^8]: https://discussions.unity.com/t/using-light-probes-in-a-custom-vert-frag-shader/866757

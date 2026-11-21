<#
.SYNOPSIS
  Gera as imagens do assistente do Inno Setup a partir do ícone do programa, para o instalador mostrar o mesmo ícone do
  programa (no lugar das figuras padrão do Inno):
    - pequena-<lado>.png: o ícone, no canto superior direito das páginas (WizardSmallImageFile);
    - grande-<largura>.png: o ícone centralizado em fundo branco, na tela de boas-vindas e na final (WizardImageFile).
  Cada uma nos tamanhos de 100% a 250% de escala da tela; o Inno escolhe a melhor. Devolve as duas listas, separadas por
  vírgula, para passar ao ISCC (/DImagemPequena=... /DImagemGrande=...) ou escrever no .iss.

.EXAMPLE
  .\ImagensInstalador.ps1 -Icone ..\OfficeManager\Source\OfficeManager\charts-colors-3d.ico -Destino ..\Output\Temp\imagens
#>
param(
    [Parameter(Mandatory)] [string] $Icone,
    [Parameter(Mandatory)] [string] $Destino
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $Destino | Out-Null

# o maior quadro do .ico (256 px nos ícones dos programas)
$ico = New-Object System.Drawing.Icon ((Resolve-Path $Icone).Path), 256, 256
$fonte = $ico.ToBitmap()

function Desenhar([int] $largura, [int] $altura, [double] $lado, [double] $topo, [bool] $fundoBranco) {
    $bmp = New-Object System.Drawing.Bitmap $largura, $altura
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear($(if ($fundoBranco) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::Transparent }))
    $x = [int](($largura - $lado) / 2)
    $g.DrawImage($fonte, $x, [int]$topo, [int]$lado, [int]$lado)
    $g.Dispose()
    return $bmp
}

$pequenas = @(); $grandes = @()
# tamanhos indicados pelo Inno para 100, 125, 150, 175, 200, 225 e 250%
foreach ($escala in 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5) {
    $lado = [int][Math]::Round(55 * $escala)
    $arq = Join-Path $Destino "pequena-$lado.png"
    $b = Desenhar $lado $lado $lado 0 $false
    $b.Save($arq, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
    $pequenas += $arq

    $largura = [int][Math]::Round(164 * $escala); $altura = [int][Math]::Round(314 * $escala)
    $arq = Join-Path $Destino "grande-$largura.png"
    $b = Desenhar $largura $altura (112 * $escala) (70 * $escala) $true
    $b.Save($arq, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose()
    $grandes += $arq
}
$fonte.Dispose(); $ico.Dispose()

[pscustomobject]@{ Pequena = ($pequenas -join ","); Grande = ($grandes -join ",") }

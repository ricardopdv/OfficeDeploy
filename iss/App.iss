; Instalador generico dos programas do OfficeManager. Gerado pelo Gerar.ps1, que passa os dados do programa:
;   /DAppId={{GUID}  (a chave dupla e o escape do Inno para "{")  /DNome="OfficeManager"  /DExe="OfficeManager.exe"  /DOrigem="<pasta preparada>"
;   /DPasta="C:\OfficeManager"  /DIcone="<.ico>"  /DSaida="<pasta dos instaladores>"  /DArquivo="Setup OfficeManager"
;   /DIniciarComWindows=1 (opcional: tarefa marcada para abrir com o Windows)
;   /DImagemPequena="<png,png...>" /DImagemGrande="<png,png...>" (opcional: imagens do assistente com o ícone do programa)
;   /DCalcRT="<pasta preparada da CalcRT>" /DJdk="<jdk-21_windows-x64_bin.exe>" (opcional: calculadora da reforma
;   tributaria em {app}\CalcRT e o JDK 21, instalado so se a maquina ainda nao tiver Java 21 ou maior)
; Atualiza por cima de uma instalacao anterior (mesmo AppId). A desinstalacao remove so os arquivos do pacote:
; o que o programa criou na pasta (logs, Update\, startup.xml...) fica.

#ifndef AppId
  #error Informe /DAppId
#endif
#define Versao GetVersionNumbersString(Origem + "\" + Exe)
#ifdef CalcRT
  #ifndef Jdk
    #error Com /DCalcRT informe tambem /DJdk
  #endif
  #define JdkArquivo ExtractFileName(Jdk)
#endif

[Setup]
AppId={#AppId}
AppName={#Nome}
AppVersion={#Versao}
VersionInfoVersion={#Versao}
AppVerName={#Nome} {#Versao}
AppPublisher=BrPDV Comercio e Servicos
DefaultDirName={#Pasta}
DefaultGroupName=OfficeManager
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
PrivilegesRequired=admin
OutputDir={#Saida}
OutputBaseFilename={#Arquivo}
SetupIconFile={#Icone}
UninstallDisplayIcon={app}\{#Exe}
; o ícone do programa também dentro do assistente (no lugar das figuras do Inno): ImagensInstalador.ps1
#ifdef ImagemPequena
WizardSmallImageFile={#ImagemPequena}
#endif
#ifdef ImagemGrande
WizardImageFile={#ImagemGrande}
#endif
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "atalho"; Description: "Criar atalho na area de trabalho"; Flags: checkedonce
#ifdef IniciarComWindows
Name: "iniciar"; Description: "Abrir o {#Nome} junto com o Windows"; Flags: checkedonce
#endif

[InstallDelete]
; o Startup.exe (verificacao de licenca em 32 bits, por causa da HID.dll) acabou: a licenca e verificada no OfficeManager
Type: files; Name: "{app}\Startup.exe"
Type: files; Name: "{app}\Startup.exe.config"

[Files]
; tudo e substituido, inclusive o .exe.config (tem os redirecionamentos de versao das DLLs);
; a configuracao do cliente fica no registro e nos arquivos que o programa cria, que nao estao no pacote
Source: "{#Origem}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifdef CalcRT
; calculadora da reforma tributaria: o programa roda "java -jar api-regime-geral.jar" em .\CalcRT. Vem so no instalador
; (nao vai no pacote de atualizacao). Troca so os arquivos mais novos que os instalados: o java em execucao prende o
; jar e os .db, e o que estiver preso e trocado no proximo reinicio do Windows.
Source: "{#CalcRT}\*"; DestDir: "{app}\CalcRT"; Flags: comparetimestamp restartreplace uninsrestartdelete recursesubdirs createallsubdirs
; JDK 21: so e extraido e instalado se a maquina ainda nao tiver Java 21 ou maior
Source: "{#Jdk}"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: not Java21Instalado
#endif

[Icons]
Name: "{autodesktop}\{#Nome}"; Filename: "{app}\{#Exe}"; WorkingDir: "{app}"; Tasks: atalho
Name: "{autoprograms}\OfficeManager\{#Nome}"; Filename: "{app}\{#Exe}"; WorkingDir: "{app}"
#ifdef IniciarComWindows
Name: "{autostartup}\{#Nome}"; Filename: "{app}\{#Exe}"; WorkingDir: "{app}"; Tasks: iniciar
#endif

[Run]
#ifdef CalcRT
Filename: "{tmp}\{#JdkArquivo}"; Parameters: "/s"; StatusMsg: "Instalando o Java (JDK 21) para a calculadora da reforma tributaria..."; Flags: waituntilterminated; Check: not Java21Instalado
#endif
; se o JDK acabou de ser instalado, o programa nao e aberto daqui: este instalador ainda tem o PATH de antes (sem o java)
; e a calculadora nao iniciaria; aberto pelo atalho, ja encontra o java
Filename: "{app}\{#Exe}"; WorkingDir: "{app}"; Description: "Abrir o {#Nome}"; Flags: nowait postinstall skipifsilent; Check: AbrirAoFinal

[Code]
#ifdef CalcRT
var
  JavaFaltava: Boolean;

{ maior versao principal de Java registrada em SOFTWARE\JavaSoft\<Tipo> (o JDK da Oracle e o Temurin registram ali) }
function MaiorJava(Tipo: String): Integer;
var
  Versoes: TArrayOfString;
  I, P, V, Raiz: Integer;
  Nome: String;
begin
  Result := 0;
  if IsWin64 then Raiz := HKLM64 else Raiz := HKLM;
  if RegGetSubkeyNames(Raiz, 'SOFTWARE\JavaSoft\' + Tipo, Versoes) then
    for I := 0 to GetArrayLength(Versoes) - 1 do
    begin
      Nome := Versoes[I];
      P := Pos('.', Nome);
      if P > 0 then Nome := Copy(Nome, 1, P - 1);
      V := StrToIntDef(Nome, 0);
      if V > Result then Result := V;
    end;
end;

{ Java 21 ou maior registrado e um java.exe no PATH (o programa chama "java" pelo PATH) }
function Java21Instalado: Boolean;
var
  Maior: Integer;
begin
  Maior := MaiorJava('JDK');
  if MaiorJava('JRE') > Maior then Maior := MaiorJava('JRE');
  Result := (Maior >= 21) and (FileSearch('java.exe', GetEnv('PATH')) <> '');
end;

function InitializeSetup: Boolean;
begin
  JavaFaltava := not Java21Instalado;
  Result := True;
end;

function AbrirAoFinal: Boolean;
begin
  Result := not JavaFaltava;
end;
#else
function AbrirAoFinal: Boolean;
begin
  Result := True;
end;
#endif

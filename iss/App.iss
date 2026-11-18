; Instalador generico dos programas do OfficeManager. Gerado pelo Gerar.ps1, que passa os dados do programa:
;   /DAppId={{GUID}  (a chave dupla e o escape do Inno para "{")  /DNome="OfficeManager"  /DExe="OfficeManager.exe"  /DOrigem="<pasta preparada>"
;   /DPasta="C:\OfficeManager"  /DIcone="<.ico>"  /DSaida="<pasta dos instaladores>"  /DArquivo="Setup OfficeManager"
;   /DIniciarComWindows=1 (opcional: tarefa marcada para abrir com o Windows)
; Atualiza por cima de uma instalacao anterior (mesmo AppId). A desinstalacao remove so os arquivos do pacote:
; o que o programa criou na pasta (logs, Update\, startup.xml...) fica.

#ifndef AppId
  #error Informe /DAppId
#endif
#define Versao GetVersionNumbersString(Origem + "\" + Exe)

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

[Files]
; tudo e substituido, inclusive o .exe.config (tem os redirecionamentos de versao das DLLs);
; a configuracao do cliente fica no registro e nos arquivos que o programa cria, que nao estao no pacote
Source: "{#Origem}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autodesktop}\{#Nome}"; Filename: "{app}\{#Exe}"; WorkingDir: "{app}"; Tasks: atalho
Name: "{autoprograms}\OfficeManager\{#Nome}"; Filename: "{app}\{#Exe}"; WorkingDir: "{app}"
#ifdef IniciarComWindows
Name: "{autostartup}\{#Nome}"; Filename: "{app}\{#Exe}"; WorkingDir: "{app}"; Tasks: iniciar
#endif

[Run]
Filename: "{app}\{#Exe}"; WorkingDir: "{app}"; Description: "Abrir o {#Nome}"; Flags: nowait postinstall skipifsilent

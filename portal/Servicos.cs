using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Downloads;

public sealed class OpcoesPortal
{
    public string ApiLogin { get; set; } = "https://update.brpdv.com.br/api/Accounts/Login";
    public string[] Papeis { get; set; } = ["Admin", "Revenda"];
    public string Pasta { get; set; } = "/var/www/update";
    public bool XAccel { get; set; } = true;
    public string PastaChaves { get; set; } = "chaves";
    public int HorasSessao { get; set; } = 8;
}

/// <summary>Usuário autenticado pelo portal das revendas.</summary>
public sealed record UsuarioRevenda(string Id, string Nome, string Email, IReadOnlyList<string> Papeis);

/// <summary>
/// Login com o mesmo usuário e senha do portal das revendas: o mesmo POST que o RevendasRazor faz em api/Accounts/Login
/// (ASP.NET Identity do site). O token vem direto da API do próprio servidor; dele saem o nome, o e-mail e os papéis.
/// </summary>
public sealed class LoginRevendas(HttpClient http, OpcoesPortal opcoes, ILogger<LoginRevendas> log)
{
    private sealed record Pedido(string nome, string email, string password, string confirmpassword);
    private sealed record Resposta(string token, DateTime expiration);

    /// <summary>O usuário, ou a mensagem de recusa para mostrar na tela.</summary>
    public async Task<(UsuarioRevenda? Usuario, string? Erro)> Entrar(string email, string senha, CancellationToken ct)
    {
        HttpResponseMessage r;
        try
        {
            // como o RevendasRazor: nome "NOVOLOGIN" e a confirmacao igual a senha (o modelo da API exige os dois)
            r = await http.PostAsJsonAsync(opcoes.ApiLogin, new Pedido("NOVOLOGIN", email, senha, senha), ct);
        }
        catch (Exception ex)
        {
            log.LogError(ex, "Login: sem resposta da API das revendas");
            return (null, "O servidor de login não respondeu. Tente de novo em alguns minutos.");
        }

        if (!r.IsSuccessStatusCode)
        {
            var texto = (await r.Content.ReadAsStringAsync(ct)).Trim().Trim('"');
            log.LogInformation("Login recusado para {Email}: {Status} {Texto}", email, (int)r.StatusCode, texto);
            return (null, (int)r.StatusCode == 400 && texto.Length is > 0 and < 120 && !texto.StartsWith('{')
                ? texto
                : "E-mail ou senha inválidos.");
        }

        var resposta = await r.Content.ReadFromJsonAsync<Resposta>(ct);
        if (string.IsNullOrEmpty(resposta?.token)) return (null, "Resposta inesperada do servidor de login.");

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(resposta.token);
        string? Valor(params string[] tipos) => jwt.Claims.FirstOrDefault(c => tipos.Contains(c.Type))?.Value;
        var papeis = jwt.Claims
            .Where(c => c.Type is "role" or "http://schemas.microsoft.com/ws/2008/06/identity/claims/role")
            .Select(c => c.Value).Distinct().ToList();

        var usuario = new UsuarioRevenda(
            Valor("ID") ?? "",
            Valor("unique_name", "name", "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name") ?? email,
            Valor("email", "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress") ?? email,
            papeis);

        if (!papeis.Any(p => opcoes.Papeis.Contains(p, StringComparer.OrdinalIgnoreCase)))
        {
            log.LogInformation("Login de {Email} sem permissão (papéis: {Papeis})", email, string.Join(",", papeis));
            return (null, "Seu usuário não tem acesso aos downloads. Fale com a BrPDV.");
        }
        return (usuario, null);
    }
}

/// <summary>Um instalador publicado (instaladores/instaladores.json, gerado pelo Gerar.ps1).</summary>
public sealed class Instalador
{
    [JsonPropertyName("arquivo")] public string Arquivo { get; set; } = "";
    [JsonPropertyName("programa")] public string Programa { get; set; } = "";
    [JsonPropertyName("versao")] public string Versao { get; set; } = "";
    [JsonPropertyName("tamanho")] public long Tamanho { get; set; }
    [JsonPropertyName("data")] public DateTime Data { get; set; }
    [JsonPropertyName("sha256")] public string Sha256 { get; set; } = "";
    /// <summary>PNG do icone do programa, relativo a instaladores/ (icones/&lt;id&gt;.png); vazio se nao houver.</summary>
    [JsonPropertyName("icone")] public string Icone { get; set; } = "";
}

/// <summary>
/// Os instaladores publicados. Lê o instaladores.json (relido quando muda: o Enviar.ps1 troca a pasta inteira);
/// sem ele, lista os .exe da pasta.
/// </summary>
public sealed class Catalogo(OpcoesPortal opcoes, IWebHostEnvironment env, ILogger<Catalogo> log)
{
    private IReadOnlyList<Instalador> _itens = [];
    private DateTime _lido = DateTime.MinValue;
    private string _origem = "";
    private readonly Lock _trava = new();

    private string Pasta => Path.Combine(Path.IsPathRooted(opcoes.Pasta) ? opcoes.Pasta : Path.Combine(env.ContentRootPath, opcoes.Pasta), "instaladores");

    public IReadOnlyList<Instalador> Instaladores()
    {
        var pasta = Pasta;
        var json = Path.Combine(pasta, "instaladores.json");
        var marca = File.Exists(json) ? File.GetLastWriteTimeUtc(json) : Directory.Exists(pasta) ? Directory.GetLastWriteTimeUtc(pasta) : DateTime.MinValue;
        lock (_trava)
        {
            if (marca == _lido && _origem == pasta) return _itens;
            _itens = Ler(pasta, json);
            (_lido, _origem) = (marca, pasta);
            return _itens;
        }
    }

    private IReadOnlyList<Instalador> Ler(string pasta, string json)
    {
        try
        {
            if (File.Exists(json))
            {
                var itens = JsonSerializer.Deserialize<List<Instalador>>(File.ReadAllText(json)) ?? [];
                return itens.Where(i => File.Exists(Path.Combine(pasta, i.Arquivo))).OrderBy(i => i.Programa).ToList();
            }
            if (!Directory.Exists(pasta)) return [];
            return new DirectoryInfo(pasta).GetFiles("*.exe").OrderBy(f => f.Name)
                .Select(f => new Instalador { Arquivo = f.Name, Programa = Path.GetFileNameWithoutExtension(f.Name).Replace("Setup ", ""), Tamanho = f.Length, Data = f.LastWriteTime })
                .ToList();
        }
        catch (Exception ex)
        {
            log.LogError(ex, "Catalogo: falha ao ler {Pasta}", pasta);
            return [];
        }
    }

    /// <summary>O instalador pelo nome exato do arquivo (nada fora do catálogo é entregue).</summary>
    public Instalador? Instalador(string arquivo) =>
        Instaladores().FirstOrDefault(i => string.Equals(i.Arquivo, arquivo, StringComparison.Ordinal));

    public string Caminho(Instalador i) => Path.Combine(Pasta, i.Arquivo);

    /// <summary>O PNG do icone, so se for o de algum instalador do catalogo (nenhum outro arquivo da pasta e entregue).</summary>
    public string? CaminhoIcone(string nome)
    {
        var item = Instaladores().FirstOrDefault(i => i.Icone.Length > 0 && string.Equals(Path.GetFileName(i.Icone), nome, StringComparison.Ordinal));
        if (item == null) return null;
        var caminho = Path.Combine(Pasta, item.Icone);
        return File.Exists(caminho) ? caminho : null;
    }
}

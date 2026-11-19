using System.Security.Claims;
using System.Threading.RateLimiting;
using Downloads;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.HttpOverrides;

var builder = WebApplication.CreateBuilder(args);
var portal = builder.Configuration.GetSection("Portal").Get<OpcoesPortal>() ?? new OpcoesPortal();
builder.Services.AddSingleton(portal);

// chaves do cookie num disco: o login continua valendo depois de reiniciar o servico
var chaves = Path.IsPathRooted(portal.PastaChaves) ? portal.PastaChaves : Path.Combine(builder.Environment.ContentRootPath, portal.PastaChaves);
builder.Services.AddDataProtection().PersistKeysToFileSystem(new DirectoryInfo(chaves)).SetApplicationName("update-portal");

builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(o =>
    {
        o.Cookie.Name = "brpdv.downloads";
        o.Cookie.HttpOnly = true;
        o.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
        o.Cookie.SameSite = SameSiteMode.Lax;
        o.LoginPath = "/entrar";
        o.LogoutPath = "/sair";
        o.AccessDeniedPath = "/entrar";
        o.ExpireTimeSpan = TimeSpan.FromHours(Math.Max(1, portal.HorasSessao));
        o.SlidingExpiration = true;
    });
builder.Services.AddAuthorization();
builder.Services.AddRazorPages(o =>
{
    o.Conventions.AuthorizeFolder("/");
    o.Conventions.AllowAnonymousToPage("/Entrar");
    o.Conventions.AllowAnonymousToPage("/Erro");
});
builder.Services.AddHttpClient<LoginRevendas>(c => c.Timeout = TimeSpan.FromSeconds(15));
builder.Services.AddSingleton<Catalogo>();

// tentativas de login: 10 por minuto por IP (o IP real vem do nginx em X-Forwarded-For)
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.OnRejected = async (ctx, ct) =>
    {
        ctx.HttpContext.Response.ContentType = "text/plain; charset=utf-8";
        await ctx.HttpContext.Response.WriteAsync("Muitas tentativas de login. Aguarde um minuto e tente de novo.", ct);
    };
    // so o envio do login conta (abrir a pagina nao)
    o.AddPolicy("login", ctx => HttpMethods.IsPost(ctx.Request.Method)
        ? RateLimitPartition.GetFixedWindowLimiter(ctx.Connection.RemoteIpAddress?.ToString() ?? "?",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 })
        : RateLimitPartition.GetNoLimiter("get"));
});
builder.Services.Configure<ForwardedHeadersOptions>(o =>
{
    o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    o.KnownProxies.Add(System.Net.IPAddress.Loopback);
});

var app = builder.Build();
app.UseForwardedHeaders();
if (!app.Environment.IsDevelopment()) app.UseExceptionHandler("/Erro");
app.UseStaticFiles();
app.UseRouting();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapRazorPages();

// download: so o arquivo que esta no catalogo; atras do nginx o arquivo sai pelo X-Accel-Redirect (location interna)
app.MapGet("/baixar/{arquivo}", (string arquivo, HttpContext http, Catalogo catalogo, ILogger<Program> log) =>
{
    var item = catalogo.Instalador(arquivo);
    if (item == null) return Results.NotFound("Instalador não encontrado.");

    var usuario = http.User.FindFirstValue(ClaimTypes.Email) ?? http.User.Identity?.Name ?? "?";
    log.LogInformation("Download {Arquivo} ({Versao}) por {Usuario} de {Ip}", item.Arquivo, item.Versao, usuario, http.Connection.RemoteIpAddress);

    if (!portal.XAccel)
        return Results.File(catalogo.Caminho(item), "application/octet-stream", item.Arquivo, enableRangeProcessing: true);

    http.Response.Headers["X-Accel-Redirect"] = "/_instaladores/" + Uri.EscapeDataString(item.Arquivo);
    http.Response.Headers.ContentDisposition = $"attachment; filename=\"{item.Arquivo}\"; filename*=UTF-8''{Uri.EscapeDataString(item.Arquivo)}";
    http.Response.ContentType = "application/octet-stream";
    return Results.Empty;
}).RequireAuthorization();

// icone do programa na lista (PNG pequeno, entregue pelo proprio app)
app.MapGet("/icone/{nome}", (string nome, HttpContext http, Catalogo catalogo) =>
{
    var caminho = catalogo.CaminhoIcone(nome);
    if (caminho == null) return Results.NotFound();
    http.Response.Headers.CacheControl = "private, max-age=3600";
    return Results.File(caminho, "image/png", lastModified: File.GetLastWriteTimeUtc(caminho));
}).RequireAuthorization();

app.MapPost("/sair", async (HttpContext http) =>
{
    await http.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
    return Results.Redirect("/entrar");
}).RequireAuthorization();

app.Run();

using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.RateLimiting;

namespace Downloads.Pages;

[EnableRateLimiting("login")]
public class EntrarModel(LoginRevendas login) : PageModel
{
    [BindProperty] public string Email { get; set; } = "";
    [BindProperty] public string Senha { get; set; } = "";
    [BindProperty(SupportsGet = true)] public string? ReturnUrl { get; set; }
    public string? Erro { get; private set; }

    public IActionResult OnGet() => User.Identity?.IsAuthenticated == true ? LocalRedirect(Destino()) : Page();

    public async Task<IActionResult> OnPostAsync(CancellationToken ct)
    {
        Email = (Email ?? "").Trim();
        if (Email.Length == 0 || string.IsNullOrEmpty(Senha))
        {
            Erro = "Informe o e-mail e a senha.";
            return Page();
        }

        var (usuario, erro) = await login.Entrar(Email, Senha, ct);
        if (usuario == null)
        {
            Erro = erro;
            return Page();
        }

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, usuario.Id),
            new(ClaimTypes.Name, usuario.Nome),
            new(ClaimTypes.Email, usuario.Email),
        };
        claims.AddRange(usuario.Papeis.Select(p => new Claim(ClaimTypes.Role, p)));
        var identidade = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
        await HttpContext.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme, new ClaimsPrincipal(identidade));
        return LocalRedirect(Destino());
    }

    private string Destino() => Url.IsLocalUrl(ReturnUrl) ? ReturnUrl! : "/";
}

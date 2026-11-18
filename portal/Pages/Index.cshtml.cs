using Microsoft.AspNetCore.Mvc.RazorPages;

namespace Downloads.Pages;

public class IndexModel(Catalogo catalogo) : PageModel
{
    public IReadOnlyList<Instalador> Itens { get; private set; } = [];

    public void OnGet() => Itens = catalogo.Instaladores();

    public static string Tamanho(long bytes) => bytes >= 1024 * 1024
        ? $"{bytes / 1024d / 1024d:N1} MB"
        : $"{Math.Max(1, bytes / 1024)} KB";
}

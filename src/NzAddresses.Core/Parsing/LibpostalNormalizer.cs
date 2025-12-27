using System.Text;
using System.Text.RegularExpressions;

namespace NzAddresses.Core.Parsing;

public class LibpostalNormalizer
{
    private static readonly Regex WhitespaceRegex = new Regex(@"\s+", RegexOptions.Compiled);

    public string Normalize(string input)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return string.Empty;
        }

        try
        {
            // For now, use a simple normalization approach
            // LibPostal integration can be enhanced if the library is available
            var normalized = input.Trim();

            // Convert to lowercase
            normalized = normalized.ToLowerInvariant();

            // Collapse multiple whitespace to single space
            normalized = WhitespaceRegex.Replace(normalized, " ");

            // Remove common punctuation
            normalized = normalized.Replace(",", " ");
            normalized = normalized.Replace(".", " ");

            // Collapse whitespace again after punctuation removal
            normalized = WhitespaceRegex.Replace(normalized, " ").Trim();

            return normalized;
        }
        catch
        {
            // Fallback to simple lowercase
            return input.Trim().ToLowerInvariant();
        }
    }

    public string[] TokenizeAndExpand(string input)
    {
        var normalized = Normalize(input);
        return normalized.Split(' ', StringSplitOptions.RemoveEmptyEntries);
    }
}

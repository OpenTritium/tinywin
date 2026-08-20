using System.Text.Json.Serialization;

namespace TinyWin.WinUI.Models;

[JsonSourceGenerationOptions(PropertyNameCaseInsensitive = true)]
[JsonSerializable(typeof(TinyWinImageInfo))]
[JsonSerializable(typeof(TinyWinImageInfo[]))]
internal sealed partial class TinyWinJsonContext : JsonSerializerContext;

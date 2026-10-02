# Windows Build Notes

## Local development (unpackaged)

```powershell
cd PlexWindows
dotnet restore
dotnet build src\PlexWindows\PlexWindows.csproj -c Debug -p:Platform=x64
dotnet run --project src\PlexWindows\PlexWindows.csproj -p:Platform=x64
```

Requires Windows 10/11 + .NET 8 SDK + Windows App SDK runtime (usually installed with VS WinUI workload).

## MSIX (Release)

```powershell
dotnet publish src\PlexWindows\PlexWindows.csproj -c Release -p:Platform=x64 -p:WindowsPackageType=MSIX
```

Output under `bin\x64\Release\net8.0-windows10.0.19041.0\win-x64\AppPackages\`.

## CI sketch (GitHub Actions, windows-latest)

```yaml
jobs:
  build-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'
      - run: dotnet restore PlexWindows/PlexWindows.sln
      - run: dotnet build PlexWindows/PlexWindows.sln -c Release -p:Platform=x64
      # Optional: publish MSIX artifact
```

Path filter recommendation: only run when `PlexWindows/**` or shared contract docs change.

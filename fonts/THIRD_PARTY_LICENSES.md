# Third-Party Font Licenses

The dotfiles, QML components, shell scripts, and Rust backend in this repository are licensed under the root [MIT License](../LICENSE).

All bundled font binaries under `fonts/` are open-source and remain governed by their respective upstream licenses:

| Directory | Font Family | Copyright / Upstream | License | License File |
| --- | --- | --- | --- | --- |
| `fonts/IBMPlexSans/` | IBM Plex Sans | IBM Corp. (`https://github.com/IBM/plex`) | SIL Open Font License 1.1 | [`OFL.txt`](IBMPlexSans/OFL.txt) |
| `fonts/IBMPlexMono/` | IBM Plex Mono | IBM Corp. (`https://github.com/IBM/plex`) | SIL Open Font License 1.1 | [`OFL.txt`](IBMPlexMono/OFL.txt) |
| `fonts/JetBrainsMono/` | JetBrains Mono | The JetBrains Mono Project Authors (`https://github.com/JetBrains/JetBrainsMono`) | SIL Open Font License 1.1 | [`OFL.txt`](JetBrainsMono/OFL.txt) |
| `fonts/SymbolsNerdFont/` | Symbols Nerd Font (Symbols Only) | Ryan McIntyre & Nerd Fonts Contributors (`https://github.com/ryanoasis/nerd-fonts`) | MIT + upstream icon-set notices (OFL 1.1 / Apache 2.0 / CC BY 4.0 / MIT) | [`LICENSE.txt`](SymbolsNerdFont/LICENSE.txt) |

No proprietary fonts are included in this repository. If you prefer to use your distribution's font packages (`ttf-jetbrains-mono` + `ttf-nerd-fonts-symbols` on Arch, `jetbrains-mono-fonts` on Fedora, `media-fonts/jetbrains-mono` + `media-fonts/symbols-nerd-font` on Gentoo), run `./install.sh --skip-fonts`.

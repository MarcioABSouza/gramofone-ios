# API consumida

O app é um **cliente fino** do Gramofone: nenhum endpoint novo, nenhuma migration. Tudo abaixo já
existe no backend (`~/Code/projects/gramofone`).

Base: `http://<servidor>:8998/api` — o `APIClient` guarda a raiz **sem** `/api` e acrescenta em
cada chamada. Autenticação por `Authorization: Bearer <access token>`.

## Sessão

| Chamada | Corpo / resposta |
|---|---|
| `POST /auth` | `{email,password}` → `{token, refreshToken, user}` |
| `POST /auth/refresh` | `{refreshToken}` → `{token, refreshToken}` (rotativo) |
| `GET /auth/me` | → `user` (`{id,name,email,role,lastfmUsername,lastfmConfigured}`) |
| `POST /auth/logout` | `{refreshToken}` (best-effort) |
| `GET /auth/config` | `{needsSetup, registrationEnabled}` — usado para avisar “servidor sem usuário” |
| `GET /health` | `{ok, service, uptime}` — botão “Testar servidor” |

## Biblioteca e álbum

| Chamada | Observações |
|---|---|
| `GET /albums?local=true&sort=&order=&skip=&take=&search=` | `{data:[Album], total, localTotal}` |
| `GET /albums/:id` | `{album, localAlbumId, trackSource, tracks[], songs[], userStatus}` |
| `GET /api/covers/:albumId` | imagem (público, sem auth) |
| `GET /api/media/<filePath>` | áudio com **Range**/seek (público, sem auth) |

`tracks[]` traz `id, number, title, artist, duration, filePath, songId, hasLyrics, hasChords`.
Quando `trackSource = "catalog"`, `filePath` é `null` → faixa não tocável.

## Filas (tocáveis)

| Chamada | Resposta |
|---|---|
| `GET /library/tracks?local=true&sort=&order=&search=` | `{data:[QueueTrack]}` (teto 1000) |
| `GET /home/lists/:kind/:id/tracks` (`kind=songs\|albums`) | `{data:[QueueTrack]}` |
| `GET /home/random?limit=` | `{data:[QueueTrack]}` |

`QueueTrack` = `{trackId, songId, title, artist, albumId, albumTitle, albumArtist,
albumArtistId, duration, filePath}` — mapeia 1:1 para `QueueItem`.

## Listas

| Chamada | Resposta |
|---|---|
| `GET /lists` | **`{data:[AlbumListSummary]}`** — atenção ao envelope |
| `GET /lists/:id` | `{list:{id,name,description,itemCount,playableCount}, items:[{position,album}]}` |
| `GET /song-lists` | `{data:[SongListSummary]}` (`system` só na lista virtual “Favoritas”) |
| `GET /song-lists/:id` | `{list:{id,name,description,system?}, items:[{position, song, localTrack}]}` |

`SongListDetail.list` **não** traz `itemCount` (o record não tem); a contagem vem de `items.length`.

## Favoritos e playlists de músicas

| Chamada | Uso |
|---|---|
| `GET /songs/:songId/interaction` | `{isFavorite, rating}` — estado do favorito da música atual |
| `POST /songs/:songId/favorite` | **alterna** o favorito e devolve o estado. Não é idempotente: em falha, reler o estado antes de tentar de novo |
| `GET /song-lists?system=1` | inclui a lista virtual **Favoritas** (`system: true`, id `favorites`) |
| `POST /song-lists/:listId/songs/:songId` | adiciona a música a uma playlist existente → 201 `{message}` |

O app só adiciona a playlists existentes (a lista `system` é filtrada do seletor). Sem rede, as
ações ficam desabilitadas.

## Reprodução e Last.fm

| Chamada | Corpo |
|---|---|
| `POST /plays` | `{trackId?, songId?, albumId?, title, artist?, albumTitle?, duration?}` |
| `POST /lastfm/scrobble` | `{title, artist?, album?, duration (int, s), playId (8–100), startedAt (unix s)}` → 202 `{queued, reason?}` |
| `POST /lastfm/scrobble/now-playing` | `{title, artist?, album?, duration (int, s)}` → 202 `{sent}` |

Regras que o app aplica no cliente (o backend valida duração mínima e janela de timestamp):
faixa **> 30 s** e **metade da duração ou 4 minutos** de reprodução real. O backend aceita
scrobble de até **14 dias** atrás — é o que permite a fila offline.

## Armadilhas de contrato (todas já tratadas no app)

1. **`duration` fracionário**: tracks vêm `252.384`. O modelo usa `Double`; formatar só na exibição.
   (Foi o bug que quebrou a tela de álbum na 0.3.0.)
2. **`GET /lists` com envelope** `{data:[…]}` — decodificar direto como array quebra
   (“resposta inesperada em raiz Array&lt;Any&gt;”).
3. **`/song-lists/:id` sem `itemCount`** no `list`.
4. **Datas**: `addedAt`/`createdAt` vêm como ISO/Date; o app **não decodifica datas** (não precisa).
5. **`/api/media` e `/api/covers` são públicos por design** — servem `<audio>`/`<img>` sem header.
6. Campos desconhecidos são ignorados pelo `JSONDecoder`; adicionar campo no backend não quebra.

## Regra de evolução

Este cliente é consumidor como o app Android: valem as regras do `AGENTS.md` do monorepo —
**só acrescentar** campo/rota, parâmetro novo é opcional, status HTTP não muda de significado.
Quebrar isso deixa versões antigas do app (que não atualizam sozinhas) inutilizáveis.

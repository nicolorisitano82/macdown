# Quattro domande, e poi l'applicazione si fa da parte

Diario breve, nella serie del [WYSIWYG](wysiwyg-testo.md), delle
[due anteprime](anteprime.md) e del [plugin drawio](drawio.md). Riguarda una
cosa piccola e delicata: **un'applicazione che si accorge di essere vecchia**.

---

## Come funziona

Quattro domande, in quest'ordine, e nessuna salta il turno:

1. **C'è una versione nuova?** Una richiesta all'elenco dei rilasci su GitHub,
   una volta al giorno, all'avvio. Se non c'è niente, non dice niente.
2. **La scarico?** Un pannello con il numero di versione, le prime righe delle
   note di rilascio, quanto pesa, e un pulsante per aprire la pagina delle note
   se si vuole leggere tutto prima di decidere.
3. **Ecco, l'ho scaricata: la apro?** L'immagine disco finisce in **Scaricati**,
   con barra di progresso, dimensioni in chiaro e un pulsante **Interrompi**
   (anche col tasto Esc) che la ferma davvero.
4. **Sì** → l'applicazione apre il `.dmg` e **si chiude**; il trascinamento su
   Applicazioni resta a mano, come sempre.

Il menù dell'applicazione ha **Controlla aggiornamenti…** per chiederlo a mano,
e **Impostazioni › Aggiornamenti** ha l'interruttore del controllo automatico,
la data dell'ultimo controllo e la versione in esecuzione.

## Cosa non fa

**Non si aggiorna da sé.** Nessuna sostituzione a sorpresa del pacchetto in
`/Applications`, nessuno script che monta e copia mentre l'app è aperta.
Sostituire l'applicazione mentre gira è il genere di scorciatoia che funziona
novantanove volte su cento; la centesima lascia un pacchetto a metà, e per
un'app senza firma Apple non c'è nemmeno un aggiornatore di sistema che rimedi.
Quindi: si scarica come si scarica qualsiasi cosa, e si installa trascinando.

**Non manda niente.** La richiesta è un `GET` all'API pubblica di GitHub con un
`User-Agent` che dice solo nome e versione. Nessun conteggio, nessun
identificatore della macchina, nessuna informazione sui documenti aperti.

**Non scarica da altrove.** L'indirizzo dell'immagine disco viene controllato
due volte — quando si legge l'elenco e di nuovo prima di scaricare — e deve
essere `https` su `github.com` o `objects.githubusercontent.com`. Un elenco
manomesso non può dirottare lo scaricamento su un altro server, ed è la ragione
per cui il controllo è una funzione a sé, con le sue prove: `github.com`
va bene, `github.com.esempio.invalid` no.

## Le versioni, che è la parte che si sbaglia

Questo progetto produce tre forme di numero e il confronto le deve capire
tutte:

| Forma | Cos'è |
|---|---|
| `v0.22.0` | il tag |
| `0.22.0` | il rilascio |
| `0.22.0d7` | sette commit dentro quello che diventerà la 0.22.0 |

La terza è la trappola: `0.22.0d7` **non è** la 0.22.0, è la strada per
arrivarci. Quindi sta dietro alla 0.22.0 e davanti alla 0.21.0 — altrimenti chi
compila da sorgente non vedrebbe mai un rilascio, o lo vedrebbe per sempre.
Un pezzo mancante è uno zero (`0.22` è `0.22.0`), e il confronto è per numeri,
non per stringhe, che è come `0.9` finirebbe dopo `0.10`.

## Come si controlla, senza cliccare

Le prove unitarie coprono confronto delle versioni, lettura dell'elenco (con
una copia di quello vero), il rifiuto degli indirizzi altrui, il nome libero in
Scaricati — `MacDownNext-0.22.0 2.dmg` quando il primo c'è già, come farebbe
il browser — la matematica della barra, l'interruttore e il limite di un
controllo al giorno. Ventidue prove.

`Tools/verify_features.sh` aggiunge la parte che le prove non possono avere:
scarica **l'elenco vero** da GitHub e lo passa allo stesso parser
dell'applicazione (`Tools/update_feed.m`), controllando che la versione letta
sia l'ultimo tag di questo repository, che l'immagine disco stia su GitHub, che
la dimensione ci sia, e che a chi ha una versione vecchia venga offerta mentre
a chi ha già quella no. Un feed che cambia forma lascerebbe l'applicazione a
non offrire mai niente, in silenzio: questo se ne accorge.

Lo scaricamento vero — progresso, interruzione, nome libero — l'ho misurato a
mano con un banco di prova sulla 0.21.0: 17 MB, `hdiutil verify` contento,
interruzione a 2 MB che non lascia file, e secondo scaricamento che diventa
`MacDownNext-0.21.0 2.dmg`.

## Dove sta il conto

| Cosa | Dove |
|---|---|
| Elenco, versioni, scaricamento | `MacDown/Code/Utility/MPUpdate.{h,m}` |
| Le quattro domande | `MacDown/Code/Application/MPUpdateController.{h,m}` |
| Pannello nelle impostazioni | `MacDown/Code/Preferences/MPUpdatePreferencesViewController.{h,m}` |
| Interruttore e data | `MPPreferences`: `updatesCheckAutomatically`, `updatesLastCheck` |
| Prove | `MacDownTests/MPUpdateTests.m` (22) |
| Controllo sul feed vero | `Tools/update_feed.m`, chiamato da `Tools/verify_features.sh` |

# Claude e GPT dentro MacDown Next: cosa si può fare davvero

Studio, non progetto: sei strade possibili, cosa danno, cosa costano, cosa
rischiano, e quali secondo me vale la pena percorrere. Nessun codice scritto,
nessuna decisione presa.

Il vincolo che tiene tutto insieme è quello che l'applicazione promette oggi
e che sta scritto sulla [pagina del progetto](../index.html): **tutto
funziona offline**, e le uniche cinque cose che escono dal Mac sono elencate
una per una. Qualunque integrazione con un motore in cloud va misurata prima
di tutto contro quella riga: se la sposta, va dietro un interruttore, e va
detto dove.

---

## Le sei strade

### A. I file di istruzioni: `CLAUDE.md` e `AGENTS.md`

Sono file Markdown, stanno nelle cartelle di lavoro, e sono **il caso d'uso
più vicino a quello che l'applicazione già fa bene**: si scrivono a mano, si
leggono a mano, e nessuno li tratta come documenti di prima classe.

Cosa potrebbe fare l'editor, tutto **in locale, senza rete**:

* riconoscere il file dal nome e offrire un **modello di partenza** — la
  cartella `Templates/` esiste già e i modelli scritti a mano ci sono;
* **risolvere le inclusioni**: `@percorso/file.md` dentro un `CLAUDE.md` tira
  dentro un altro file, e oggi per sapere cosa vede davvero il motore bisogna
  aprirli a uno a uno. Un pannello che mostra l'albero risolto è lo stesso
  lavoro dei [backlink](anteprime.md), già fatto una volta;
* dire **quale file vince**: utente (`~/.claude/CLAUDE.md`), progetto, locale.
  È una gerarchia, e una gerarchia si disegna;
* controlli di forma nel pannello della prosa: sezioni vuote, inclusioni
  rotte, file che nessuno include.

**Costo**: basso. Tutto codice che assomiglia a codice già scritto.
**Rischio**: il formato può cambiare sotto di noi, ma il danno è un pannello
che mostra meno, non un documento rovinato. **Prova**: banale — sono funzioni
pure su testo, come `MPBacklinks` o `MPTaskList`.

### B. I comandi di scrittura anche via cloud

Oggi *migliora, correggi, rendi formale, accorcia* girano su un modello GGUF
locale attraverso llama.cpp. Gli stessi comandi potrebbero, **a scelta**,
passare per l'API di Anthropic o di OpenAI: risposta migliore su testi
lunghi, nessun modello da scaricare, nessuna RAM occupata.

Quanto costa **al documento**, sul serio, ai prezzi di listino:

| Motore | Modello | Ingresso $/M | Uscita $/M |
|---|---|---|---|
| Anthropic | `claude-opus-5` | 5,00 | 25,00 |
| Anthropic | `claude-sonnet-5` | 2,00 | 10,00 |
| Anthropic | `claude-haiku-4-5` | 1,00 | 5,00 |
| OpenAI | GPT‑5.6 Sol | 4,00 | 20,00 |
| OpenAI | GPT‑5.6 Terra | 2,00 | 12,00 |
| OpenAI | GPT‑5.6 Luna | 0,20 | 1,20 |

Un verbale di duemila parole sono ~3 000 token: riscriverlo con Sonnet 5
costa meno di due centesimi, con Haiku meno di uno. **Il costo non è il
problema**; il problema è cosa esce dal Mac.

Come si terrebbe onesta:

* chiave nel **Portachiavi**, mai nelle preferenze, mai nei log;
* interruttore esplicito, spento di serie, con scritto sopra *cosa* viene
  mandato (la selezione, o il paragrafo) e *a chi*;
* la risposta arriva in **streaming** e un solo annulla la porta via — la
  macchina per farlo c'è già, è quella del modello locale;
* ogni chiamata finisce nel **registro delle azioni**, se acceso.

**Costo**: medio. Un client HTTP per due API diverse, gestione della chiave,
errori di rete, e la tentazione di reimplementare metà SDK. **Rischio**: è la
prima cosa che sposta la riga «niente esce dal Mac», e va detto in prima
pagina, non in fondo alle preferenze. **Prova**: le parti pure (costruzione
della richiesta, lettura dello stream, conteggio dei token) su fixture; una
sola prova viva nella suite di controllo, come già si fa con l'elenco dei
rilasci.

### C. Un server MCP sulla cartella — l'integrazione al contrario

Invece di mandare il documento al motore, si lascia che **il motore chieda i
documenti**: un piccolo server MCP che espone la cartella di lavoro con
strumenti espliciti — cerca, leggi, scrivi, elenca i backlink — e Claude Code
o Claude Desktop lo montano.

È l'integrazione più utile per chi tiene una cartella di verbali, ed è già in
[roadmap alla fase 3](roadmap-bear.md). Rispetto a B, ha due qualità: il
perimetro lo decide l'utente (quale cartella, quali strumenti), e
l'applicazione non manda niente da sé — è l'altro capo a chiedere.

**Costo**: medio-alto. Un binario a parte, un protocollo da rispettare,
permessi da disegnare. **Rischio**: uno strumento «scrivi» su una cartella di
documenti va progettato con la stessa cura di un `rm`. **Prova**: il
protocollo è JSON su stdio — si prova con fixture, senza rete.

### D. Importare conversazioni e artifact

Le conversazioni di Claude e di ChatGPT si esportano (JSON, e gli artifact
sono già Markdown). Un importatore che ne fa un documento pulito — front
matter con data e origine, i blocchi di codice interi, le tabelle
mantenute — è **lo stesso lavoro del ritaglio web**, che esiste e funziona.

**Costo**: basso, riusa `MPMarkdownFromRichText` e la macchina del front
matter. **Rischio**: i formati di esportazione cambiano, ma un importatore
che non riconosce un file lo dice e non rovina niente. **Prova**: fixture
degli export, come per il feed dei rilasci.

### E. Sincronizzare i file con Projects e con i vector store

Caricare la cartella nei Projects di Claude o nei file di OpenAI, tenerli
allineati, cancellare quelli rimossi.

**Costo**: alto, e continuo: due API diverse, stato da mantenere, conflitti
da risolvere, quote da gestire. **Rischio**: è sincronizzazione, cioè la
categoria di problemi che sembra facile per tre settimane. **Valore**: basso
per chi già avrebbe il server MCP della strada C, che risolve lo stesso
bisogno senza copiare niente da nessuna parte.

### F. «Apri in Claude», «Apri in ChatGPT»

Una voce di menù che apre l'app o il sito con il documento negli appunti, o
via schema URL dove esiste. Dieci righe.

**Costo**: nullo. **Rischio**: nullo. **Valore**: piccolo ma vero, ed è la
cosa che la gente si aspetta per prima.

---

## Il quadro

| Strada | Valore | Costo | Sposta la riga della privacy | Verdetto |
|---|---|---|---|---|
| A — file di istruzioni | alto | basso | no | **farla** |
| B — comandi via cloud | medio | medio | **sì** | farla, ma **come plug-in** |
| C — server MCP | alto | medio-alto | no (il perimetro lo dà l'utente) | **farla**, dopo A |
| D — importare conversazioni | medio | basso | no | farla quando serve |
| E — sincronizzare i Projects | basso | alto | sì | **no** |
| F — «apri in…» | basso | nullo | no | farla subito |

## La cosa che rende B accettabile: farla fuori dal nucleo

Da oggi l'applicazione ha [un contratto per i plug-in che aggiungono
formati](../guide#exporting) — `MPExporterPlugIn` — e il caricatore dei
plug-in che c'era dal 2016. La stessa idea regge un plug-in che parla con un
motore in cloud:

* il nucleo resta quello che dice di essere: **niente esce dal Mac**;
* chi vuole Claude o GPT **installa un plug-in**, e installarlo è la
  decisione informata che un interruttore in fondo a un pannello non è;
* il plug-in porta la sua chiave, il suo pannello, i suoi errori, e si può
  togliere;
* la promessa in prima pagina resta vera senza asterischi.

Serve un pezzo che ancora non c'è: un contratto per i plug-in che **agiscono
sul testo** (prendi questa selezione, restituisci un rimpiazzo), fratello di
quello degli esportatori. È lavoro piccolo e già disegnato, perché il modello
locale fa esattamente quella forma di lavoro.

## Se si decide di procedere, in quest'ordine

1. **F**, un pomeriggio: «Apri in Claude / ChatGPT».
2. **A**, una settimana: riconoscere `CLAUDE.md` e `AGENTS.md`, risolvere le
   inclusioni, mostrare la gerarchia, controllarne la forma.
3. Il **contratto dei plug-in che agiscono sul testo**, sul modello di
   `MPExporterPlugIn`, con il modello locale come primo cliente — così il
   contratto nasce provato.
4. **B come plug-in**, uno per Anthropic e uno per OpenAI, chiave nel
   Portachiavi.
5. **C**, il server MCP, quando la fase 3 arriva in cima alla lista.
6. **D** quando serve davvero. **E** mai.

---

*Prezzi Anthropic: listino API di prima parte (giugno 2026). Prezzi OpenAI:
[pagina dei prezzi](https://developers.openai.com/api/docs/pricing) — da
riverificare prima di scriverli in un'interfaccia, cambiano.*

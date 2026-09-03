# L'aiuto alla scrittura, in locale

Diario del lavoro, come per il [WYSIWYG](wysiwyg-testo.md). Serve a chi
riprende in mano questa parte: **quello che è stato misurato, e le due volte
che la misura ha smentito me.**

---

## Il principio da cui non allontanarsi

Il documento resta la stringa che hai scritto. Un modello **propone testo**,
non modifica il file per conto suo: ogni comando sostituisce una selezione,
in **un passo di annullamento**, e quello che non ti piace se ne va con ⌘Z.

E niente esce dalla macchina. Non è una scelta di prudenza: è la ragione per
cui questa cosa può stare in un editor di note di collaudo.

---

## La prova sul campo, prima di tutto

L'ordine è stato: **prima il motore**, poi i comandi, poi il pannello. Non è
l'ordine in cui si vedono i risultati, è l'ordine del rischio: se llama.cpp
non compilava o era troppo lento, tutto il resto era lavoro buttato.

Costa meno di quanto avessi stimato. Avevo detto «una ventina di megabyte»:

| | |
|---|---|
| Compilazione (M3 Max) | **25 secondi**, tag `b6300` |
| Librerie statiche | **~5,5 MB** in tutto |
| Shader Metal | incorporati: niente `.metallib` da spedire |
| Generazione, 3 B | 89 token/s |

Statiche e non dinamiche: un'app che collega qualche `.a` è un binario solo,
senza cinque dylib da copiare nel bundle, install name da correggere e firme
da mettere. E compilate dal **loro** CMake tramite `Tools/build_llama.sh`,
non piegate dentro il target Xcode: riprodurre quali sorgenti servono in una
build solo-Metal e come si incorporano gli shader sarebbe un secondo sistema
di compilazione da tenere allineato a un progetto che si muove ogni giorno.

### Il vincolo è la taglia, non il motore

Stessa richiesta — «riscrivi in tono formale» — ai due estremi:

- **0,5 B (469 MB)**: `collaudo` → «**concorso**», e «risoltamente
  rispettate», che non è italiano. Ha rotto il senso.
- **3 B (2,0 GB)**: «Il collaudo si è concluso con successo, non abbiamo
  identificato problemi significativi.»

**Il pavimento è 3 B, cioè 2 GB di download.** Non è un dettaglio del
pannello: è la sua ragione d'essere.

---

## I template non li genera il modello

Al 3 B ho chiesto un verbale di collaudo. Ha prodotto:

```
| Causi di prova | Esito |
```

«Causi». E cinque righe numerate senza colonne per descrizione, atteso e
riscontrato; e «Firmato:» ripetuto cinque volte invece di un blocco firme.

**Una struttura ha una forma giusta, e un modello la indovina ogni volta da
capo.** Quindi le forme sono scritte a mano una volta e tenute come file. Si
guadagna tutto: struttura deterministica, nessun titolo inventato,
istantanei, traducibili — e **funzionano senza nessun modello installato**.

Il modello resta perfetto per l'altra metà: riformulare quello che c'è già.

---

## La lezione più costosa: nominare la lingua

Questa è la volta in cui ho creduto di migliorare e ho **rotto**.

Nello spike l'istruzione diceva «Riscrivi il testo che ricevi **in
italiano**». Funzionava. Passando alla fase 2 l'ho «migliorata»: istruzioni
più curate, con *keeping its meaning* e *keep the Markdown formatting*, e la
lingua non più nominata ma descritta — «answer in the same language as the
text».

Misurato dopo, su un paragrafo italiano:

| istruzione | risultato |
|---|---|
| quella «migliorata» | **il testo identico all'ingresso** |
| senza le clausole conservative | riscritto **in spagnolo** |
| corta e diretta | riscritto **in inglese** |
| con la lingua **nominata** | riscritto in italiano, correttamente |

Due cose insieme, e vanno lette insieme. Le clausole conservative erano
l'unica cosa che tenevano il modello in italiano, **e lo facevano non
cambiando nulla**: la funzione sembrava funzionare e restituiva l'ingresso.
Togliendole, il modello traduce.

La correzione: la lingua si **rileva** (`NLLanguageRecognizer`) e si
**nomina** — «the text is in Italian, and your answer must be in Italian».
Provato per italiano, inglese e tedesco.

> Un modello piccolo non ragiona su «la stessa lingua del testo». Segue un
> nome proprio.

E ne segue una conclusione sulle traduzioni: chiesta la stessa cosa con
l'istruzione in inglese e in italiano, il modello risponde allo stesso modo.
Quello che segue è la **lingua d'uscita nominata**, non la lingua in cui gli
si parla. Quindi **le istruzioni non si traducono**: una formulazione da
tenere buona invece di ventisei.

---

## Le tre cose silenziose

Tutte e tre passavano inosservate perché non davano errore.

**`NSTextView` senza finestra non ha un undo manager.** È `nil`, non un
errore: ogni registrazione finiva nel vuoto e il test dell'annullamento
*falliva affermando la cosa giusta*.

**Una voce di menu con un sottomenu ha un'azione.** `submenuAction:`, data da
AppKit. La mia ricerca del menu dei template richiedeva `action == NULL`,
quindi non trovava nulla, il delegato non veniva mai impostato, e il menu
usciva **vuoto**. Avevo dato la colpa all'identificatore nel nib, in un
commento; poi l'ho verificato con `ibtool` — c'è, era innocente.

**Gli `edgeInsets` di uno stack view non sopravvivono all'essere contenuto di
un `NSGlassEffectView`.** Il pannello veniva alto quanto il suo testo, zero
margine. Vincoli espliciti, che non sono interpretabili.

---

## L'attesa che non aveva niente da mostrare

Al primo comando dopo l'installazione Metal compila gli shader incorporati:
**~3,5 secondi** in cui l'app sembrava aver ignorato la richiesta.

Prima toglievo la selezione subito, perché il documento non sembrasse
intatto. Era lo scambio sbagliato: **un paragrafo che sparisce e resta
sparito tre secondi è peggio di uno che aspetta.** Ora il testo resta finché
non c'è qualcosa da metterci, e l'attesa è dichiarata da uno spinner che
distingue le due cose — aprire il modello e rispondere — perché chi vede
solo una rotella non sa se il modello è lento o bloccato.

Gli shader si compilano **durante il caricamento**, generando un token e
buttandolo. Non rende il primo comando più veloce in totale: **sposta** quel
lavoro dentro un'attesa che si può spiegare.

Misurato dove la cache di sistema è già calda: riscaldamento 0,08 s, primo
token da 160 a **96 ms**, in linea con tutti i successivi. I 3,5 secondi li
ho visti prima e non li posso riprodurre adesso — la cache è di sistema.

---

## Perché un protocollo e non una classe

`MPTextGenerator` è un protocollo perché quello che genera le parole
cambierà più di una volta: il GGUF locale è un'implementazione, il modello
di sistema di macOS 26 sarà l'altra, e **i comandi nell'editor non devono
poter distinguere chi ha risposto**.

Si è ripagato subito: con un generatore finto, tutta l'interazione — cosa
viene sostituito, cosa riprende un annulla, cosa lascia un fallimento, che
un secondo comando è rifiutato mentre il primo gira — è provata **senza
modello su disco e senza GPU**.

---

## Cosa non fare

**Non completare mentre si digita.** Sembra la prima cosa da fare ed è la
peggiore qui: entra in conflitto col nascondimento dei marcatori, col salto
del cursore sui delimitatori e con l'annullamento in un passo. E un
suggerimento che appare mentre pensi interrompe la scrittura invece di
aiutarla.

**Non aggiungere una chat laterale.** Un editor ha già il posto giusto per
il testo: il testo. Una chat aggiunge un pannello, uno stato, una cronologia
e la domanda «e adesso come lo metto nel documento?».

**Non tradurre il documento intero.** Un 3 B su un documento lungo perde la
struttura markdown a metà strada. Se serve, va fatto blocco per blocco
usando gli offset di sorgente che la sincronizzazione già usa.

**Non generare strutture.** Vedi «Causi di prova».

---

## Dove tenere d'occhio le interazioni

- **L'annullamento.** Lo streaming è tante modifiche, e ogni giro del run
  loop sarebbe un gruppo suo: senza raggruppamento, sei comandi costano
  trenta ⌘Z. È l'unica cosa che va riprovata a ogni modifica del flusso.
- **La memoria.** Un modello caricato tiene qualche giga. Si scarica da sé
  dopo dieci minuti; se qualcuno aggiunge un secondo posto da cui caricarlo,
  quel timer va ripensato.
- **Il primo avvio.** Tutto quello che riguarda la latenza va misurato su una
  cache degli shader fredda, che è la sola condizione in cui il difetto si
  vede — e non si può ricreare a comando.

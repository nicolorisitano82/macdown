# Il codice: in linea o in un recinto

Diario breve, nella serie del [WYSIWYG](wysiwyg-testo.md) e
dell'[aiuto alla scrittura](ai-locale.md). Riguarda un pulsante solo, ma con
dentro una cosa che valeva la pena scoprire.

---

## Il pulsante faceva metà del lavoro

`Inline Code` metteva due backtick attorno alla selezione. Corretto, e
insufficiente: il codice di più di una riga vuole un **recinto**, e un
recinto senza linguaggio è una scatola grigia. Il linguaggio è il punto —
è quello che accende l'evidenziazione.

Quindi il pulsante ora chiede: **dentro la riga**, o **un blocco
evidenziato come…**. Se la selezione contiene un a capo la prima delle due
non è possibile, e la domanda si riduce al linguaggio.

Il comando si disfà da sé, come gli altri: una selezione già fra backtick
li perde, e le righe di un blocco già recintato perdono il recinto.

---

## La lista non me la sono inventata

Centotredici voci. Non sono i linguaggi che esistono: sono quelli che
**questa copia sa evidenziare davvero**, e l'elenco nasce dall'incrocio di
tre cose che devono essere d'accordo:

1. il catalogo di Prism (`Prism/components.js`), che dà i nomi leggibili —
   `cpp` è C++, `csharp` è C#, e in un menù serve il secondo;
2. i file dei componenti presenti nel bundle, perché il catalogo si copia
   intero e i componenti si scelgono;
3. la mappa degli alias di MacDown Next, che decide dove finisce un nome
   scritto a mano.

Un alias entra nella lista solo se Prism gli dà un nome (`aliasTitles`) e la
mappa lo risolve: così ci sono HTML e XML, che si leggono come linguaggi, e
non ci sono `js` o `py`, che ripeterebbero voci già presenti. E non ci
sono nomi che darebbero un recinto grigio.

Ventisei linguaggi comuni stanno sopra una riga di separazione. Non è un
giudizio sui linguaggi: è che centotredici voci in un menù significano
scorrere oltre ABAP per arrivare a Python.

---

## La misura che ha trovato un difetto vecchio

Costruendo la lista è saltato fuori questo, in `syntax_highlighting.json`:

```json
"json": "javascript",
```

Un alias scritto quando Prism non aveva un componente JSON. Prism ce l'ha,
è nel bundle, e quell'alias glielo portava via: **per anni ```json è stato
colorato come JavaScript.** Una riga in meno e torna al suo componente.

Il caso è tutelato da un test che non guarda `json` in particolare, ma
l'invariante: *nessun alias può togliere un nome a un componente che quel
nome ce l'ha già.* Il difetto tornerebbe identico, e il test lo prenderebbe.

---

## Dove sta il conto

Il calcolo — quali righe prende il recinto, dove va il cursore dopo — sta in
`MPCodeLanguages.m`, fuori dall'editor, e restituisce un `MPCodeFenceEdit`:
intervallo, testo, selezione. Il documento fa tre righe. Non è pulizia: è
che quel conto lo sbaglio, e fuori dall'editor lo si può controllare senza
una finestra. Cinque prove lo fanno, `MPCodeLanguageTests`.

---

## Il rientro, col destro, secondo il linguaggio

Dentro un blocco recintato il menù contestuale ha una voce sua: **Rientra
come Python**, **Rientra come JavaScript** — il nome è quello del
linguaggio scritto sul recinto, risolto attraverso la mappa degli alias,
così `js` e `c++` trovano la loro regola.

La voce compare solo a due condizioni: il linguaggio ha una regola, e la
regola **cambierebbe davvero qualcosa**. Un comando che non fa niente quando
lo premi insegna a non premerlo più.

### Tre famiglie, non una

Una regola sola per tutti avrebbe rovinato due terzi dei casi:

| Famiglia | Chi | Cosa fa |
|---|---|---|
| Parentesi | C, C++, C#, Java, Objective-C, PHP, Rust, Swift, Kotlin, Go, JavaScript, TypeScript, JSON, CSS, SCSS, Less | La profondità la dicono le graffe: il rientro si ricalcola da zero |
| Tag | HTML, XML | La profondità la dicono i tag, void e autochiusi esclusi |
| Offside | Python, Ruby, YAML, Bash, CoffeeScript, Makefile | **Il rientro è la sintassi**: si cambia solo il passo, mai la struttura |

Per gli altri ottanta e più linguaggi la regola non c'è, e la voce non
compare. Evidenziare vuole una grammatica di simboli; impaginare vuole una
grammatica di blocchi. Solo la seconda è dichiarata qui, e dichiararla dove
non c'è è il modo di rovinare il codice di qualcuno.

### Le cose che non si toccano

Tre casi in cui il comando **lascia stare**, e ognuno è una prova:

- **Quello che sta dentro una stringa che va a capo.** Un template literal
  in JavaScript, un docstring in Python: quelle righe sono testo, il loro
  rientro è parte di ciò che la stringa dice. Restano come scritte, e nel
  caso offside non entrano nemmeno nella misura.
- **I commenti su più righe.** Gli asterischi in colonna se ne vanno se li
  reindenti.
- **Il codice allineato invece che rientrato.** Argomenti sotto la parentesi
  aperta: se le rientrature del blocco sono 4 e 11, non esiste un passo che
  misuri entrambe, e moltiplicare quelle colonne fa un disastro. Il blocco
  torna identico.

Nella famiglia offside il passo del blocco è il **massimo comun divisore**
delle sue rientrature. Un divisore di uno spazio non è un passo: è il segno
che dentro c'è dell'allineamento, e allora non si tocca niente. E se il
passo è già quello che il linguaggio vuole, non si fa nulla — non per
pigrizia: riscrivere per riscrivere trascinerebbe il contenuto delle
stringhe lunghe.

Un `Makefile` è il caso in cui il passo non è gusto: una riga di ricetta
deve iniziare con un tab, e con gli spazi il file non funziona.

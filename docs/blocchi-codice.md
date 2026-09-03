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

# L'editor che mostra il testo

Le preferenze in **Preferenze › Resa grafica › Scrittura** che cambiano
come l'editor *disegna* il markdown e come si comporta mentre scrivi.
Nessuna di loro cambia cosa viene salvato: il documento resta la stringa
che vedi in un editor di testo.

Questo file va guardato **nell'editor**, non nell'anteprima. Accendi e
spegni le preferenze mentre lo hai davanti.

## Scala i titoli con il carattere dell'editor

I temi dell'editor dichiarano i corpi dei titoli in punti, scelti per il
corpo predefinito. Ingrandendo il testo i titoli restano dov'erano, e oltre
una certa dimensione diventano più piccoli del testo normale. Con questa
accesa le proporzioni del tema vengono mantenute a qualsiasi corpo.

Prova: porta il carattere dell'editor a 24pt e guarda il titolo qui sopra.

## Nascondi i marcatori finché il cursore non arriva

Qui sotto ci sono **grassetto**, *corsivo*, `codice in linea` e un
[link a un sito](https://example.org). Con la preferenza accesa vedi le
parole senza i simboli intorno; porta il cursore dentro una di loro e i
simboli tornano.

I caratteri non sono spariti: sono ancora nel file, e sono solo i glifi a
non essere disegnati. Un `**` cancellato non lascia l'altro orfano — toglie
il grassetto e lascia la parola.

Il [link di riferimento][rif] è lasciato in chiaro di proposito: nascondere
`[rif]` toglierebbe l'unico modo di sapere quale definizione stai usando.

[rif]: https://example.org

## Rientra liste e citazioni nell'editor

- Una voce di lista con abbastanza testo da andare a capo, per far vedere
  che la seconda riga si allinea con la parola e non con il trattino
- Una seconda voce
- Una terza

1. Anche le liste numerate, con del testo lungo abbastanza da spezzarsi su
   più di una riga
2. Seconda voce

> Una citazione, con la sua barra nel margine.
> La barra resta continua anche quando una riga va a capo da sola e non ha
> un simbolo di citazione tutto suo.

## Allinea le colonne delle tabelle

| Trimestre | Ricavi | Margine |
|:---|---:|:---:|
| Q1 | 12400 | 18,2% |
| Secondo trimestre | 15900 | 21,7% |
| Q3 | 141 | 19,4% |

Le barre si allineano anche se le celle hanno lunghezze diverse. Nel file
restano esattamente i caratteri che vedi in un editor di testo: non viene
aggiunto nemmeno uno spazio. Aggiungi una parola lunga a una cella e la
colonna si allarga da sola quando ti fermi a scrivere.

Con il cursore dentro una cella che contiene enfasi i marcatori
ricompaiono, e quella riga si allarga finché non esci: è la stessa
rivelazione dei marcatori, vista dal lato della larghezza.

## Incolla il testo formattato come markdown

Copia un pezzo di pagina web — un titolo, un elenco, una tabella — e
incollalo qui: arriva come markdown, non come una riga di testo che una
volta era un titolo.

Funziona con quello che i browser mettono negli appunti insieme al testo
semplice. Riconosce titoli, elenchi anche annidati, collegamenti,
immagini, blocchi di codice con il loro linguaggio, citazioni e tabelle.
Quello che non riconosce lascia passare il testo e basta.

**⌘⇧V** (*Modifica › Incolla senza formattazione*) incolla invece il testo
esattamente com'era.

## I marcatori collassano da soli

Scrivi `**una prova**` qui sotto e guarda cosa succede quando batti il
secondo asterisco: gli asterischi spariscono nel momento in cui il
costrutto è completo, senza dover spostare il cursore.

E con il cursore subito dopo una parola in grassetto, il tasto di
cancellazione toglie la lettera che vedi, non i marcatori che non vedi.
Quando resta una lettera sola, il costrutto se ne va tutto insieme.

## ⌘B e ⌘I sulla parola

Metti il cursore dentro una parola qualsiasi di questa riga e premi ⌘B:
la parola diventa grassetta senza doverla selezionare. Premi di nuovo e
torna com'era. Lo stesso vale per ⌘I, ⌘K e il codice in linea.

## Le due insieme

Con **entrambe** accese, tre trattini smettono di essere tre trattini e
diventano una linea attraverso la pagina:

---

Serve che siano accese sia **Nascondi i marcatori** sia **Rientra liste e
citazioni**: una linea disegnata accanto a tre trattini visibili sarebbero
due righe orizzontali invece di una.

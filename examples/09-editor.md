# L'editor che mostra il testo

Le tre preferenze in **Preferenze › Resa grafica › Scrittura** che cambiano
come l'editor *disegna* il markdown. Nessuna di loro cambia cosa viene
salvato: il documento resta la stringa che vedi in un editor di testo.

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

## Le due insieme

Con **entrambe** accese, tre trattini smettono di essere tre trattini e
diventano una linea attraverso la pagina:

---

Serve che siano accese tutte e due: una linea disegnata accanto a tre
trattini visibili sarebbero due righe orizzontali invece di una.

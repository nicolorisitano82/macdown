# La piegatura delle sezioni

Questo file va guardato **nell'editor**, non nell'anteprima: la piegatura è
una cosa dell'editor, e il file su disco resta la stringa che vedi in
qualunque altro programma.

Nel margine sinistro, accanto a ogni titolo, c'è un **chevron**: in giù
quando la sezione è aperta, a destra quando è piegata. Cliccalo, oppure usa
**⌥⌘←** e **⌥⌘→** dal menù *Vista*; con shift piegano e aprono tutto.

## Una sezione con abbastanza righe da valere la pena

Piega questa e vedrai il conteggio delle righe apparire contro il margine
destro. Il conteggio sta lì e non dopo le parole per una ragione: quando il
cursore arriva sul titolo compaiono i `##`, la riga si allarga, e un
conteggio appoggiato al testo scivolerebbe di lato ogni volta.

Il documento non cambia di un carattere: i glifi vengono soltanto
soppressi, come già succede ai marcatori di *corsivo* e **grassetto**.

Terza riga, per avere qualcosa da contare.
Quarta riga.
Quinta riga.

## Una sezione con una sottosezione dentro

Il corpo di una sezione arriva fino al titolo successivo che non le sta
sotto. Quindi piegando **questa** spariscono anche la sottosezione qui
sotto e il suo contenuto — e con loro il suo chevron, che non ha senso
mostrare per un titolo che non è sulla pagina.

### La sottosezione

Ha un chevron suo, e si piega da sola senza toccare la sezione che la
contiene. Prova prima questa, poi quella sopra.

Due righe di contenuto.

### Una seconda sottosezione

Così si vede che una sezione può averne più di una.

## Titoli senza corpo

### Questo non ha niente sotto

### E nemmeno questo

Un titolo senza niente da nascondere ha un chevron **inerte**: disegnato
più tenue, e non cliccabile. È disegnato comunque perché un segno che
compare e sparisce mentre scrivi dà più fastidio di uno a volte inattivo —
e mentre scrivi un titolo acquista e perde il suo corpo di continuo.

## Quello che la piegatura non tocca

I cancelletti dentro un recinto di codice non sono titoli:

```sh
# questo è un commento, non una sezione
echo "e questa non è una riga da piegare"
```

E un `# così` in linea nemmeno.

## Cosa succede al cursore

Se la selezione entra in una sezione piegata, quella si apre: nessuno
dovrebbe scrivere in un testo che non vede. E piegando la sezione dove sta
il cursore, il cursore va sul titolo.

Prova: piega questa sezione, poi cerca una parola che sta qui dentro con
⌘F — la sezione si riapre da sé.

Parola da cercare: **melagrana**.

## L'ultima sezione del documento

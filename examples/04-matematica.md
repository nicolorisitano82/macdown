# Matematica

Con **Sintassi matematica in stile TeX** accesa, le formule vengono
composte da MathJax, che è incluso nell'applicazione: non serve alcuna
connessione.

## In linea

L'energia a riposo è $E = mc^2$, e la costante di Eulero vale
$e = \sum_{n=0}^{\infty} \frac{1}{n!}$ dentro la riga di testo.

Il delimitatore `$` in linea si può spegnere nelle preferenze, se scrivi
spesso di prezzi e non vuoi che `$5` diventi una formula. Con quello spento
restano `\(` e `\)`, che vanno scritti con la barra raddoppiata perché il
markdown se ne mangia una: \\(a^2 + b^2 = c^2\\).

## In blocco

$$
\int_{0}^{\infty} e^{-x^{2}}\,dx = \frac{\sqrt{\pi}}{2}
$$

$$
\begin{pmatrix} a & b \\ c & d \end{pmatrix}
\begin{pmatrix} x \\ y \end{pmatrix} =
\begin{pmatrix} ax + by \\ cx + dy \end{pmatrix}
$$

$$
\frac{\partial u}{\partial t}
= h^{2}\left(
\frac{\partial^{2} u}{\partial x^{2}}
+ \frac{\partial^{2} u}{\partial y^{2}}
\right)
$$

## Somme, limiti, radici

$$
\lim_{n \to \infty}\left(1 + \frac{1}{n}\right)^{n} = e
\qquad
\sqrt[3]{\frac{27}{8}} = \frac{3}{2}
$$

## Nelle esportazioni

Le formule non restano sorgente TeX quando esporti: vengono composte e
messe nel file come disegni, così si vedono anche dove non c'è MathJax —
in un EPUB su un lettore, o in un documento Word.

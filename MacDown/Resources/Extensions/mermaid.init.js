// MacDown mermaid bootstrap.
//
// Three things make this different from a plain "render on load" script.
//
// First, the preview is refreshed by replacing the document's innerHTML.
// That does not re-execute <script> tags, so binding to the load event only
// ever rendered the first version of a document: every keystroke afterwards
// left the fences as bare code blocks. window.mermaid does survive the swap,
// so this exposes MacDownRenderMermaid() and MacDown calls it after each
// refresh instead.
//
// Second, the diagram theme has to follow the system appearance, otherwise a
// light diagram sits in the middle of a dark page.
//
// Third, a diagram is fitted to the width of the preview pane, and a big one
// (a wide gantt, a long flowchart) gets squeezed until its labels overlap.
// Each diagram is therefore wrapped in a zoomable viewport: pinch or
// ctrl-scroll to magnify part of it, drag to pan, double-click to fit again.
//
// Written in ES5 on purpose, to match the rest of the bundled extensions.
// mermaid's render became asynchronous in version 10, and is driven here
// through .then rather than async/await for the same reason.

(function () {

  var darkQuery = window.matchMedia
    ? window.matchMedia("(prefers-color-scheme: dark)")
    : null;

  var counter = 0;

  // Zoom survives a refresh: you would otherwise lose your place in a large
  // diagram on every keystroke. Keyed by the diagram's position in the
  // document, which is stable as long as you are not adding fences above it.
  var zoomStates = {};

  var MAX_ZOOM_FACTOR = 12;

  // Width mermaid is asked to lay a gantt out at. Its default axisFormat is
  // %Y-%m-%d, ten characters per tick, and at the width of a preview pane the
  // date axis collides with itself. Laying it out wide and then fitting it
  // keeps the labels apart; zoom is what makes them readable again.
  var GANTT_LAYOUT_WIDTH = 1600;

  function currentTheme() {
    return (darkQuery && darkQuery.matches) ? "dark" : "forest";
  }

  function configure() {
    mermaid.initialize({
      startOnLoad: false,
      theme: currentTheme(),
      flowchart: {
        htmlLabels: false,
        useMaxWidth: true
      },
      gantt: {
        useWidth: GANTT_LAYOUT_WIDTH
      }
    });
  }


  /* ---------------------------------------------------------------- zoom */

  // The rendered SVG's own coordinate space, which is what the viewport is
  // sized from. mermaid is inconsistent about how it expresses this: some
  // diagrams carry width/height attributes, others only a viewBox, and with
  // useMaxWidth it sets a percentage width and a max-width style.
  function intrinsicSize(svg) {
    var w = 0;
    var h = 0;

    var box = svg.getAttribute("viewBox");
    if (box) {
      var parts = box.split(/[\s,]+/);
      if (parts.length === 4) {
        w = parseFloat(parts[2]) || 0;
        h = parseFloat(parts[3]) || 0;
      }
    }

    // A gantt comes back with viewBox="0 0 0 <height>" from this version of
    // mermaid: the height is right, the width is simply missing. Its own
    // getBBox is no help either, reporting tens of thousands of units of
    // off-canvas scratch geometry, so fall back to the width we asked for.
    if (!(w > 0))
      w = GANTT_LAYOUT_WIDTH;

    if (!(h > 0)) {
      var rect = svg.getBoundingClientRect();
      h = rect.height > 0 ? rect.height : 0;
    }

    // Whatever we settled on has to be in the viewBox as well, or scaling the
    // element scales a coordinate space that does not match the drawing.
    if (w > 0 && h > 0)
      svg.setAttribute("viewBox", "0 0 " + w + " " + h);

    return { width: w, height: h };
  }

  function makeZoomable(holder, svg, stateKey) {
    var size = intrinsicSize(svg);
    if (!size.width || !size.height)
      return;

    // Lay the SVG out at its own size; the transform below does the fitting,
    // so that zooming is a change of one number rather than a relayout.
    svg.removeAttribute("width");
    svg.removeAttribute("height");
    svg.style.maxWidth = "none";
    svg.style.width = size.width + "px";
    svg.style.height = size.height + "px";

    var canvas = document.createElement("div");
    canvas.className = "mermaid-diagram-canvas";
    holder.insertBefore(canvas, svg);
    canvas.appendChild(svg);

    var view = {
      fit: 1,
      scale: 1,
      x: 0,
      y: 0
    };

    function clamp(scale) {
      var min = view.fit;
      var max = view.fit * MAX_ZOOM_FACTOR;
      return Math.min(max, Math.max(min, scale));
    }

    // Panning is bounded so the diagram cannot be flung off screen.
    function clampOffsets() {
      var visibleW = holder.clientWidth;
      var visibleH = holder.clientHeight;
      var scaledW = size.width * view.scale;
      var scaledH = size.height * view.scale;

      var minX = Math.min(0, visibleW - scaledW);
      var minY = Math.min(0, visibleH - scaledH);
      view.x = Math.min(0, Math.max(minX, view.x));
      view.y = Math.min(0, Math.max(minY, view.y));

      // Centre whichever axis still has slack.
      if (scaledW < visibleW)
        view.x = (visibleW - scaledW) / 2;
      if (scaledH < visibleH)
        view.y = (visibleH - scaledH) / 2;
    }

    function apply() {
      clampOffsets();
      canvas.style.transform =
        "translate(" + view.x + "px," + view.y + "px) scale(" + view.scale + ")";
      if (view.scale > view.fit + 0.0001)
        holder.className = "mermaid-diagram is-pannable";
      else
        holder.className = "mermaid-diagram";
      zoomStates[stateKey] = { scale: view.scale, x: view.x, y: view.y };
    }

    function refit(keepZoom) {
      var visibleW = holder.clientWidth;
      if (!visibleW)
        return;
      var previous = view.fit;
      view.fit = Math.min(1, visibleW / size.width);
      holder.style.height = (size.height * view.fit) + "px";
      if (keepZoom && previous)
        view.scale = clamp(view.scale * (view.fit / previous));
      else
        view.scale = view.fit;
      apply();
    }

    // Zoom about a point so the thing under the cursor stays under it, which
    // is the whole point of zooming "part of" a diagram.
    function zoomAt(clientX, clientY, factor) {
      var rect = holder.getBoundingClientRect();
      var px = clientX - rect.left;
      var py = clientY - rect.top;

      var next = clamp(view.scale * factor);
      if (next === view.scale)
        return;

      var ratio = next / view.scale;
      view.x = px - (px - view.x) * ratio;
      view.y = py - (py - view.y) * ratio;
      view.scale = next;
      apply();
    }

    // A plain wheel must keep scrolling the page. ctrl/meta+wheel is how a
    // trackpad pinch arrives outside WebKit's own gesture events.
    holder.addEventListener("wheel", function (e) {
      if (!e.ctrlKey && !e.metaKey)
        return;
      e.preventDefault();
      // Gentle on purpose: one notch of a mouse wheel is deltaY 120, and a
      // steeper base would jump from fit to the zoom ceiling in a single tick.
      zoomAt(e.clientX, e.clientY, Math.pow(0.998, e.deltaY));
    }, false);

    // WebKit reports trackpad pinches as gesture events instead.
    var gestureStartScale = 1;
    holder.addEventListener("gesturestart", function (e) {
      e.preventDefault();
      gestureStartScale = view.scale;
    }, false);
    holder.addEventListener("gesturechange", function (e) {
      e.preventDefault();
      var target = clamp(gestureStartScale * e.scale);
      zoomAt(e.clientX, e.clientY, target / view.scale);
    }, false);

    var dragging = false;
    var lastX = 0;
    var lastY = 0;

    holder.addEventListener("mousedown", function (e) {
      // Below the fit scale there is nothing to pan, and swallowing the
      // event there would break selecting the text around the diagram.
      if (view.scale <= view.fit + 0.0001 || e.button !== 0)
        return;
      dragging = true;
      lastX = e.clientX;
      lastY = e.clientY;
      holder.className = "mermaid-diagram is-panning";
      e.preventDefault();
    }, false);

    document.addEventListener("mousemove", function (e) {
      if (!dragging)
        return;
      view.x += e.clientX - lastX;
      view.y += e.clientY - lastY;
      lastX = e.clientX;
      lastY = e.clientY;
      apply();
    }, false);

    document.addEventListener("mouseup", function () {
      if (!dragging)
        return;
      dragging = false;
      apply();
    }, false);

    holder.addEventListener("dblclick", function (e) {
      e.preventDefault();
      if (view.scale > view.fit + 0.0001)
        refit(false);
      else
        zoomAt(e.clientX, e.clientY, 3);
    }, false);

    var controls = document.createElement("div");
    controls.className = "mermaid-zoom-controls";
    [
      ["−", "Zoom out", function () {
        var r = holder.getBoundingClientRect();
        zoomAt(r.left + r.width / 2, r.top + r.height / 2, 1 / 1.4);
      }],
      ["▢", "Fit", function () { refit(false); }],
      ["+", "Zoom in", function () {
        var r = holder.getBoundingClientRect();
        zoomAt(r.left + r.width / 2, r.top + r.height / 2, 1.4);
      }]
    ].forEach(function (spec) {
      var button = document.createElement("button");
      button.type = "button";
      button.textContent = spec[0];
      button.title = spec[1];
      button.addEventListener("click", function (e) {
        e.preventDefault();
        spec[2]();
      }, false);
      controls.appendChild(button);
    });
    holder.appendChild(controls);

    refit(false);

    // Layout is not always settled when the render callback runs, and a fit
    // measured against a zero or stale width leaves the diagram at the wrong
    // scale. Measure again once the current work is done, and after load.
    window.setTimeout(function () { refit(false); }, 0);
    window.addEventListener("load", function () { refit(false); }, false);

    // Restore where the reader was before the refresh.
    var saved = zoomStates[stateKey];
    if (saved && saved.scale > view.fit) {
      view.scale = clamp(saved.scale);
      view.x = saved.x;
      view.y = saved.y;
      apply();
    }

    if (window.addEventListener) {
      window.addEventListener("resize", function () {
        refit(true);
      }, false);
    }
  }


  /* -------------------------------------------------------------- render */

  // The fence arrives as <pre><code class="language-mermaid">. Swapping the
  // <pre> out for a plain container drops the code block's frame and
  // background, which would otherwise box the finished diagram.
  function containerFor(block) {
    var target = block;
    if (block.tagName === "CODE"
        && block.parentElement
        && block.parentElement.tagName === "PRE") {
      target = block.parentElement;
    }
    if (!target.parentNode)
      return null;

    var holder = document.createElement("div");
    holder.className = "mermaid-diagram";
    target.parentNode.replaceChild(holder, target);
    return holder;
  }

  function renderAll() {
    if (typeof mermaid === "undefined")
      return;

    var blocks = document.querySelectorAll(".language-mermaid");
    if (!blocks.length)
      return;

    configure();

    for (var i = 0; i < blocks.length; i++) {
      renderOne(blocks[i], "d" + i);
    }
  }

  // A malformed diagram must not take the rest of the page down with it, and
  // while you are typing one it is malformed most of the time. Since mermaid
  // 10 the failure arrives as a rejected promise rather than a throw, so both
  // paths end up in the same handler.
  function renderOne(block, stateKey) {
    var source = block.innerText || block.textContent;
    var holder = containerFor(block);
    if (!holder)
      return;

    var id = "macdown-mermaid-" + (counter++);

    function succeeded(result) {
      // mermaid 10 resolves to an object; older releases handed the string
      // to a callback. Accept either, so a downgrade does not go silent.
      var svgCode = (result && result.svg) ? result.svg : result;
      holder.innerHTML = svgCode;
      var svg = holder.querySelector("svg");
      if (svg)
        makeZoomable(holder, svg, stateKey);
    }

    function failed(e) {
      holder.className = "mermaid-diagram mermaid-error";
      holder.style.height = "";
      holder.textContent = String(e && e.message ? e.message : e);

      // mermaid leaves its scratch element behind when a render fails.
      var orphan = document.getElementById(id);
      if (orphan && orphan.parentNode)
        orphan.parentNode.removeChild(orphan);
    }

    try {
      var outcome = mermaid.render(id, source);
      if (outcome && typeof outcome.then === "function")
        outcome.then(succeeded, failed);
      else
        succeeded(outcome);
    } catch (e) {
      failed(e);
    }
  }

  window.MacDownRenderMermaid = renderAll;

  if (darkQuery) {
    var onSchemeChange = function () { renderAll(); };
    if (darkQuery.addEventListener)
      darkQuery.addEventListener("change", onSchemeChange);
    else if (darkQuery.addListener)
      darkQuery.addListener(onSchemeChange);
  }

  if (document.readyState === "complete"
      || document.readyState === "interactive") {
    renderAll();
  } else {
    window.addEventListener("load", renderAll, false);
  }
})();

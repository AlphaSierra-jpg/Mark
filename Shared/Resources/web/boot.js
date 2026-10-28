/*
 * Mark — renderer bootstrap.
 *
 * Runs inside the WKWebView. The native side calls `Mark.setMarkdown(string)`
 * (via evaluateJavaScript) for the initial render and again on every file
 * change, so a reload never throws away the scroll position.
 */
(function () {
  "use strict";

  marked.use({ gfm: true, breaks: false });

  var content = document.getElementById("mark-content");
  var usedIds = Object.create(null);

  function slugify(text) {
    var base = String(text)
      .trim()
      .toLowerCase()
      .replace(/[\s]+/g, "-")
      .replace(/[^\w\-À-￿]/g, "");
    if (!base) base = "section";
    if (usedIds[base] === undefined) {
      usedIds[base] = 0;
      return base;
    }
    usedIds[base] += 1;
    return base + "-" + usedIds[base];
  }

  function addHeadingIds(root) {
    usedIds = Object.create(null);
    var headings = root.querySelectorAll("h1, h2, h3, h4, h5, h6");
    for (var i = 0; i < headings.length; i++) {
      headings[i].id = slugify(headings[i].textContent);
    }
  }

  function highlight(root) {
    var blocks = root.querySelectorAll("pre code");
    for (var i = 0; i < blocks.length; i++) {
      try {
        hljs.highlightElement(blocks[i]);
      } catch (error) {
        /* An unknown language must never break the whole render. */
      }
    }
  }

  function freezeInputs(root) {
    var inputs = root.querySelectorAll("input");
    for (var i = 0; i < inputs.length; i++) {
      inputs[i].disabled = true;
    }
  }

  // The document grows and shrinks between renders, and images settle late.
  // Re-applying over a few frames keeps the viewport where the reader left it.
  function restoreScroll(y) {
    window.scrollTo(0, y);
    requestAnimationFrame(function () {
      window.scrollTo(0, y);
      requestAnimationFrame(function () {
        window.scrollTo(0, y);
      });
    });
    setTimeout(function () {
      window.scrollTo(0, y);
    }, 120);
  }

  window.Mark = {
    setMarkdown: function (source) {
      var previousScroll = window.scrollY;
      content.innerHTML = marked.parse(String(source));
      addHeadingIds(content);
      highlight(content);
      freezeInputs(content);
      restoreScroll(previousScroll);
      return true;
    },

    scrollOffset: function () {
      return window.scrollY;
    },

    scrollTo: function (y) {
      restoreScroll(y);
      return true;
    }
  };
})();

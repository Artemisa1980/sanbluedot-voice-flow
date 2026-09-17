// Presentation state only: no audio, storage, network, clipboard or native bridge.
(() => {
  const modes = {
    literal: ['No rewriting model. Only the corrections you have confirmed.', 'On device'],
    clean: ['Conservative punctuation and verified filler removal. Keep the raw version.', 'Text provider required'],
    translate: ['An explicit rewrite from Spanish or mixed speech into English.', 'Text provider required'],
    notes: ['Structure one spoken thought into notes and action items.', 'Text provider required']
  };
  const libraries = {
    history: ['A place to return to your words.', 'No personal history is loaded. The finished hub would keep raw and delivered versions available under your retention settings.'],
    vocabulary: ['Names worth getting right.', 'No personal vocabulary is loaded. Manage names, acronyms and technical terms explicitly, with each entry visible and removable.'],
    snippets: ['A short phrase. A complete thought.', 'No personal snippets are loaded. A saved trigger would expand into your signature, a reusable prompt, a link or a full block of text.']
  };
  let recording = false;
  function setRecording(value) {
    recording = value;
    document.querySelectorAll('[data-record-button]').forEach(b => {
      b.textContent = value ? 'End state preview' : 'Preview recording';
      b.setAttribute('aria-pressed', String(value));
    });
    document.querySelectorAll('[data-record-state]').forEach(n => n.textContent = value ? 'ON AIR PREVIEW' : 'READY PREVIEW');
    document.querySelectorAll('[data-wave]').forEach(n => n.dataset.recording = String(value));
    document.querySelectorAll('[data-mode]').forEach(b => b.disabled = value);
    document.querySelectorAll('[data-preview-hint]').forEach(n => n.textContent = value ? 'Simulated appearance only. Microphone remains off.' : 'Visual demonstration only. No audio is captured.');
  }
  const pages = Array.from(document.querySelectorAll('[data-page]'));
  function selectPage(button) {
    setRecording(false);
    pages.forEach(b => { b.setAttribute('aria-selected', String(b === button)); b.tabIndex = b === button ? 0 : -1; });
    document.querySelectorAll('[data-panel]').forEach(n => n.hidden = n.dataset.panel !== button.dataset.page);
  }
  pages.forEach((button, index) => {
    button.addEventListener('click', () => selectPage(button));
    button.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight' || event.key === 'ArrowDown') next = (index + 1) % pages.length;
      else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') next = (index + pages.length - 1) % pages.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = pages.length - 1;
      else return;
      event.preventDefault(); selectPage(pages[next]); pages[next].focus();
    });
  });
  document.querySelectorAll('[data-mode]').forEach(button => button.addEventListener('click', () => {
    if (recording) return;
    const [description, route] = modes[button.dataset.mode];
    document.querySelectorAll('[data-mode]').forEach(b => b.setAttribute('aria-pressed', String(b === button)));
    document.querySelectorAll('[data-mode-description]').forEach(n => n.textContent = description);
    document.querySelectorAll('[data-route]').forEach(n => n.textContent = route);
    document.querySelectorAll('[data-mode-name]').forEach(n => n.textContent = button.dataset.mode.toUpperCase());
  }));
  document.querySelectorAll('[data-record-button]').forEach(b => b.addEventListener('click', () => setRecording(!recording)));
  document.querySelectorAll('[data-library]').forEach(button => button.addEventListener('click', () => {
    const [title, description] = libraries[button.dataset.library];
    document.querySelectorAll('[data-library]').forEach(b => b.setAttribute('aria-pressed', String(b === button)));
    document.querySelector('[data-library-title]').textContent = title;
    document.querySelector('[data-library-description]').textContent = description;
  }));
})();

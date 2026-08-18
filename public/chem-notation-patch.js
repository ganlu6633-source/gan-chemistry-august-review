(() => {
  const style = document.createElement('style')
  style.textContent = '.chem-symbol sup{font-size:.68em;line-height:0;vertical-align:.5em;margin-left:.03em;font-style:normal;text-transform:none}'
  document.head.append(style)

  const unitPattern = /^(mol|mL|μL|µL|L|s|min|h|g|kg|m|cm|mm|dm|Pa|kPa|J|kJ|K|V|A|Ω)(?:·)?([-−]\d+)$/
  const tokenPattern = /(?:\b(?:mol|mL|μL|µL|L|s|min|h|g|kg|m|cm|mm|dm|Pa|kPa|J|kJ|K|V|A|Ω)(?:·)?[-−]\d+)|(?:\b(?:\d+)?(?:[A-Z][a-z]?|\((?:[A-Z][a-z]?)+\d*\))+(?:\d+)?(?:\^\d*[+-]|[+-])?)/g

  function splitCharge(value) {
    const explicit = value.match(/\^(\d*)([+-])$/)
    if (explicit) return { body: value.slice(0, -explicit[0].length), digits: explicit[1], sign: explicit[2] }
    const sign = value.match(/([+-])$/)
    if (!sign) return { body: value, digits: '', sign: '' }
    const rawBody = value.slice(0, -sign[0].length)
    const singleElementCharge = rawBody.match(/^(?:[A-Z][a-z]?)(\d+)$/)
    if (singleElementCharge) return { body: rawBody.slice(0, -singleElementCharge[1].length), digits: singleElementCharge[1], sign: sign[1] }
    return { body: rawBody, digits: '', sign: sign[1] }
  }

  function appendFormula(parent, value) {
    const charge = splitCharge(value)
    const body = charge.body
    const wrapper = document.createElement('span')
    wrapper.className = 'chem-symbol'
    wrapper.setAttribute('aria-label', value)

    let index = 0
    let hasAtom = false
    while (index < body.length) {
      if (/\d/.test(body[index])) {
        let end = index + 1
        while (end < body.length && /\d/.test(body[end])) end += 1
        const node = document.createTextNode(body.slice(index, end))
        if (hasAtom) {
          const sub = document.createElement('sub')
          sub.textContent = node.textContent
          wrapper.append(sub)
        } else {
          wrapper.append(node)
        }
        index = end
        continue
      }
      wrapper.append(body[index])
      hasAtom = body[index] === ')' || /[A-Za-z]/.test(body[index]) || hasAtom
      index += 1
    }

    if (charge.sign) {
      const sup = document.createElement('sup')
      sup.textContent = `${charge.digits}${charge.sign}`
      wrapper.append(sup)
    }
    parent.append(wrapper)
  }

  function appendToken(parent, value) {
    const unit = value.match(unitPattern)
    if (unit) {
      const wrapper = document.createElement('span')
      wrapper.className = 'chem-symbol'
      wrapper.setAttribute('aria-label', value)
      wrapper.append(unit[1])
      const sup = document.createElement('sup')
      sup.textContent = unit[2].replace('-', '−')
      wrapper.append(sup)
      parent.append(wrapper)
      return
    }
    if (/\d|[+-]/.test(value)) appendFormula(parent, value)
    else parent.append(value)
  }

  function formatElement(element) {
    if (element.dataset.chemNotationReady === 'true') return
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT)
    const textNodes = []
    let node
    while ((node = walker.nextNode())) {
      if (node.parentElement?.closest('.chem-symbol')) continue
      if (tokenPattern.test(node.nodeValue || '')) textNodes.push(node)
      tokenPattern.lastIndex = 0
    }

    textNodes.forEach((textNode) => {
      const value = textNode.nodeValue || ''
      const fragment = document.createDocumentFragment()
      let lastIndex = 0
      tokenPattern.lastIndex = 0
      let match
      while ((match = tokenPattern.exec(value))) {
        fragment.append(value.slice(lastIndex, match.index))
        appendToken(fragment, match[0])
        lastIndex = match.index + match[0].length
      }
      fragment.append(value.slice(lastIndex))
      textNode.replaceWith(fragment)
    })
    element.dataset.chemNotationReady = 'true'
  }

  const chemistryTextSelectors = [
    '.source-transcription p, .source-transcription li',
    '.question-card h1, .question-card .option-list button, .answer-explanation p',
    '.knowledge-card h1, .knowledge-card .core-rule, .knowledge-card p, .knowledge-card li',
    '.record-knowledge-grid b, .record-knowledge-grid p, .record-knowledge-grid span',
    '.record-question-stem, .record-question summary p, .record-option-list p, .record-answer-row b, .record-explanation p',
    '.record-topics span, .record-skill-summary h3, .record-next-step span',
    '.guardian-card li, .timeline b, .timeline p',
    '.video-card h3, .video-skill, .teacher-video-reason p, .guardian-video-reason',
    '.preview-today h3, .preview-today p, .preview-week b, .preview-week p',
  ].join(', ')

  function scan(root = document) {
    const elements = []
    if (root.matches?.(chemistryTextSelectors)) elements.push(root)
    root.querySelectorAll?.(chemistryTextSelectors).forEach((element) => elements.push(element))
    elements.forEach(formatElement)
  }

  scan()
  new MutationObserver((records) => {
    records.forEach((record) => record.addedNodes.forEach((node) => {
      if (node.nodeType === Node.ELEMENT_NODE) scan(node)
    }))
  }).observe(document.documentElement, { childList: true, subtree: true })
})()

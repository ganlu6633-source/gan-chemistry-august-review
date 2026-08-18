(() => {
  const style = document.createElement('style')
  style.textContent = '.chem-symbol sup{font-size:.68em;line-height:0;vertical-align:.5em;margin-left:.03em;font-style:normal;text-transform:none}'
  document.head.append(style)

  const unitPattern = /^(mol|L|s|min|g|kg|Pa|kPa)(?:·)?([-−]\d+)$/
  const tokenPattern = /(?:\b(?:mol|L|s|min|g|kg|Pa|kPa)(?:·)?[-−]\d+)|(?:\b(?:\d+)?(?:[A-Z][a-z]?|\((?:[A-Z][a-z]?)+\d*\))+\d*)/g

  function appendFormula(parent, value) {
    const charge = value.match(/(\d*)([+-])$/)
    const body = charge ? value.slice(0, -charge[0].length) : value
    const singleElementCharge = charge && /^(?:[A-Z][a-z]?)\d+$/.test(body)
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
        if (hasAtom && !singleElementCharge) {
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

    if (singleElementCharge && charge) {
      const sup = document.createElement('sup')
      sup.textContent = `${body.match(/\d+$/)?.[0] ?? ''}${charge[2]}`
      wrapper.append(sup)
    } else if (charge) {
      const sup = document.createElement('sup')
      sup.textContent = `${charge[1]}${charge[2]}`
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

  function scan(root = document) {
    root.querySelectorAll?.('.source-transcription p, .source-transcription li').forEach(formatElement)
  }

  scan()
  new MutationObserver((records) => {
    records.forEach((record) => record.addedNodes.forEach((node) => {
      if (node.nodeType === Node.ELEMENT_NODE) scan(node)
    }))
  }).observe(document.documentElement, { childList: true, subtree: true })
})()

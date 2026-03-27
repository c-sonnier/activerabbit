import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "aiToggle", "aiKnob", "aiCard", "aiPrice",
    "uptimeSlider", "uptimePrice", "uptimeValue", "uptimeCard",
    "errorsSlider", "errorsPrice", "errorsValue", "errorsCard",
    "replaySlider", "replayPrice", "replayValue", "replayCard",
    "totalMonthly", "totalSection", "summaryBox", "itemList",
    "tierTeam", "tierBusiness", "freqAnnual", "freqMonthly"
  ]

  static prices = {
    team:     { monthly: 29, annual: 26 },
    business: { monthly: 80, annual: 72 }
  }

  connect() {
    this.aiEnabled = false
    this.selectedTier = "team"
    this.selectedFrequency = "monthly"
    // Ensure button states match defaults
    this._toggleButton(this.tierTeamTarget, true)
    this._toggleButton(this.tierBusinessTarget, false)
    this._toggleButton(this.freqMonthlyTarget, true)
    this._toggleButton(this.freqAnnualTarget, false)
    // Initialize card highlights for default values
    var uptimeVal = parseInt(this.uptimeSliderTarget.value)
    this._highlightCard(this.uptimeCardTarget, uptimeVal > 0, "#059669", "#f0fdf4")
    this.uptimePriceTarget.textContent = "$" + ((uptimeVal / 10) * 10)

    var replayVal = parseInt(this.replaySliderTarget.value)
    this._highlightCard(this.replayCardTarget, replayVal > 0, "#2563eb", "#eff6ff")
    this.replayPriceTarget.textContent = "$" + (Math.ceil(replayVal / 5000) * 14)
    this.updateTotal()
  }

  selectTier(event) {
    this.selectedTier = event.currentTarget.dataset.plan
    this._toggleButton(this.tierTeamTarget, this.selectedTier === "team")
    this._toggleButton(this.tierBusinessTarget, this.selectedTier === "business")
    this.updateTotal()
  }

  selectFrequency(event) {
    this.selectedFrequency = event.currentTarget.dataset.frequency
    this._toggleButton(this.freqAnnualTarget, this.selectedFrequency === "annual")
    this._toggleButton(this.freqMonthlyTarget, this.selectedFrequency === "monthly")
    this.updateTotal()
  }

  _toggleButton(btn, active) {
    if (active) {
      btn.style.background = "#fff"
      btn.style.color = "#111827"
      btn.style.boxShadow = "0 1px 2px rgba(0,0,0,0.08)"
    } else {
      btn.style.background = "transparent"
      btn.style.color = "#6b7280"
      btn.style.boxShadow = "none"
    }
  }

  toggleAi() {
    this.aiEnabled = !this.aiEnabled
    var toggle = this.aiToggleTarget
    var knob = this.aiKnobTarget
    var card = this.aiCardTarget

    if (this.aiEnabled) {
      toggle.style.backgroundColor = "#7c3aed"
      knob.style.transform = "translateX(20px)"
      card.style.borderColor = "#7c3aed"
      card.style.backgroundColor = "#faf5ff"
      this.aiPriceTarget.textContent = "$40"
    } else {
      toggle.style.backgroundColor = "#d1d5db"
      knob.style.transform = "translateX(0px)"
      card.style.borderColor = "#e5e7eb"
      card.style.backgroundColor = "#ffffff"
      this.aiPriceTarget.textContent = "$0"
    }
    this.updateTotal()
  }

  updateUptime() {
    var val = parseInt(this.uptimeSliderTarget.value)
    var price = (val / 10) * 10
    this.uptimePriceTarget.textContent = "$" + price
    this.uptimeValueTarget.textContent = val + " monitors"
    this._highlightCard(this.uptimeCardTarget, val > 0, "#059669", "#f0fdf4")
    this.updateTotal()
  }

  updateErrors() {
    var val = parseInt(this.errorsSliderTarget.value)
    var price = (val / 100000) * 14
    this.errorsPriceTarget.textContent = "$" + price
    if (val >= 1000000) {
      this.errorsValueTarget.textContent = "1M errors/mo"
    } else if (val > 0) {
      this.errorsValueTarget.textContent = (val / 1000) + "K errors/mo"
    } else {
      this.errorsValueTarget.textContent = "0 errors/mo"
    }
    this._highlightCard(this.errorsCardTarget, val > 0, "#dc2626", "#fef2f2")
    this.updateTotal()
  }

  updateReplay() {
    var val = parseInt(this.replaySliderTarget.value)
    var price = Math.ceil(val / 5000) * 14
    this.replayPriceTarget.textContent = "$" + price
    if (val >= 1000000) {
      this.replayValueTarget.textContent = "1M sessions"
    } else if (val > 0) {
      this.replayValueTarget.textContent = (val / 1000) + "K sessions"
    } else {
      this.replayValueTarget.textContent = "0 sessions"
    }
    this._highlightCard(this.replayCardTarget, val > 0, "#2563eb", "#eff6ff")
    this.updateTotal()
  }

  _highlightCard(card, active, borderColor, bgColor) {
    if (active) {
      card.style.borderColor = borderColor
      card.style.backgroundColor = bgColor
    } else {
      card.style.borderColor = "#e5e7eb"
      card.style.backgroundColor = "#ffffff"
    }
  }

  updateTotal() {
    var prices = this.constructor.prices
    var basePriceMonthly = prices[this.selectedTier][this.selectedFrequency]
    var tierLabel = this.selectedTier.charAt(0).toUpperCase() + this.selectedTier.slice(1)

    var addonTotal = 0
    var items = []

    // Plan base line
    items.push({ name: "Plan Base (" + tierLabel + ")", price: basePriceMonthly })

    if (this.aiEnabled) {
      addonTotal += 40
      items.push({ name: "AI Error Analysis", price: 40 })
    }

    var uptime = parseInt(this.uptimeSliderTarget.value)
    if (uptime > 0) {
      var p = (uptime / 10) * 10
      addonTotal += p
      items.push({ name: uptime + " Uptime Monitors", price: p })
    }

    var errors = parseInt(this.errorsSliderTarget.value)
    if (errors > 0) {
      var p2 = (errors / 100000) * 14
      addonTotal += p2
      var label = errors >= 1000000 ? "1M" : (errors / 1000) + "K"
      items.push({ name: label + " Extra Errors", price: p2 })
    }

    var replay = parseInt(this.replaySliderTarget.value)
    if (replay > 0) {
      var p3 = Math.ceil(replay / 5000) * 14
      addonTotal += p3
      var rlabel = replay >= 1000000 ? "1M" : (replay / 1000) + "K"
      items.push({ name: rlabel + " Session Replays", price: p3 })
    }

    var monthly = basePriceMonthly + addonTotal

    this.totalMonthlyTarget.textContent = "$" + monthly.toLocaleString()

    var annual = monthly * 12
    var monthlyPrices = this.constructor.prices
    var monthlyBase = monthlyPrices[this.selectedTier].monthly
    var annualBase = monthlyPrices[this.selectedTier].annual
    var monthlyTotal = monthlyBase + addonTotal
    var annualTotal = (annualBase + addonTotal) * 12
    var savings = (monthlyTotal * 12) - annualTotal

    if (this.selectedFrequency === "annual") {
      this.totalSectionTarget.innerHTML =
        '<div style="display: flex; justify-content: space-between; align-items: baseline;">' +
          '<span style="font-size: 13px; color: #6b7280;">Total annual cost</span>' +
          '<span style="font-size: 20px; font-weight: 800; color: #111827;">$' + annualTotal.toLocaleString() + '</span>' +
        '</div>' +
        '<div style="font-size: 11px; color: #9ca3af; margin-top: 2px;">/yr &middot; billed annually</div>'
    } else {
      this.totalSectionTarget.innerHTML =
        '<div style="display: flex; justify-content: space-between; align-items: baseline;">' +
          '<span style="font-size: 13px; color: #6b7280;">Total monthly cost</span>' +
          '<span style="font-size: 20px; font-weight: 800; color: #111827;">$' + monthly.toLocaleString() + '</span>' +
        '</div>' +
        '<div style="display: flex; justify-content: space-between; align-items: baseline; margin-top: 8px;">' +
          '<span style="font-size: 12px; color: #6b7280;">Annual price</span>' +
          '<span style="font-size: 14px; font-weight: 700; color: #059669;">$' + annualTotal.toLocaleString() + '/yr</span>' +
        '</div>' +
        (savings > 0 ? '<div style="font-size: 11px; color: #059669; margin-top: 2px; text-align: right;">Save $' + savings.toLocaleString() + '/yr with annual billing</div>' : '')
    }

    // Build line items
    var html = ""
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      html += '<div style="display: flex; justify-content: space-between; padding: 4px 0; font-size: 13px;">'
      html += '<span style="color: #6b7280;">' + item.name + '</span>'
      html += '<span style="color: #111827; font-weight: 600;">$' + item.price + '</span>'
      html += '</div>'
    }
    this.itemListTarget.innerHTML = html
  }
}

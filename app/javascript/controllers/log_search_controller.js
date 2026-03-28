import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "query", "detail"]

  search() {
    this.formTarget.requestSubmit()
  }

  toggleDetail(event) {
    const tr = event.currentTarget
    if (!tr || tr.tagName !== "TR") return
    const next = tr.nextElementSibling
    if (next && next.hasAttribute("data-log-detail-id")) {
      next.classList.toggle("hidden")
    }
  }
}

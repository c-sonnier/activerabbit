import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "query", "detail"]

  search() {
    this.formTarget.requestSubmit()
  }

  toggleDetail(event) {
    const row = event.currentTarget
    const entryId = row.dataset.logEntryId
    const detail = row.querySelector(`[data-log-detail-id="${entryId}"]`)

    if (detail) {
      detail.classList.toggle("hidden")
    }
  }
}

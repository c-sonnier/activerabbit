import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["master", "severityGroup", "severity"]

  toggle() {
    const enabled = this.masterTarget.checked
    this.severityGroupTarget.classList.toggle("opacity-50", !enabled)
    this.severityGroupTarget.classList.toggle("pointer-events-none", !enabled)
  }
}

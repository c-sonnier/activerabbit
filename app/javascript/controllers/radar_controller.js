import { Controller } from "@hotwired/stimulus"
import Chart from "chart.js/auto"

export default class extends Controller {
  static values = {
    labels: Array,
    scores: Array,
    maxScores: Array
  }

  connect() {
    const ctx = this.element.getContext("2d")

    this.chart = new Chart(ctx, {
      type: "radar",
      data: {
        labels: this.labelsValue,
        datasets: [
          {
            label: "Score",
            data: this.scoresValue,
            backgroundColor: "rgba(99, 102, 241, 0.15)",
            borderColor: "rgba(99, 102, 241, 0.9)",
            borderWidth: 2,
            pointBackgroundColor: "rgba(99, 102, 241, 1)",
            pointBorderColor: "#fff",
            pointBorderWidth: 2,
            pointRadius: 5,
            pointHoverRadius: 7,
          },
          {
            label: "Max",
            data: this.maxScoresValue,
            backgroundColor: "rgba(229, 231, 235, 0.12)",
            borderColor: "rgba(209, 213, 219, 0.5)",
            borderWidth: 1,
            borderDash: [4, 4],
            pointRadius: 0,
            pointHoverRadius: 0,
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (item) => {
                if (item.datasetIndex === 1) return null
                const max = this.maxScoresValue[item.dataIndex] || 0
                return `${item.label}: ${item.raw} / ${max}`
              }
            },
            filter: (item) => item.datasetIndex === 0
          }
        },
        scales: {
          r: {
            beginAtZero: true,
            max: Math.max(...this.maxScoresValue, 40),
            ticks: {
              stepSize: 10,
              color: "#9ca3af",
              backdropColor: "transparent",
              font: { size: 10 }
            },
            grid: {
              color: "rgba(229, 231, 235, 0.6)",
              circular: true
            },
            angleLines: {
              color: "rgba(229, 231, 235, 0.6)"
            },
            pointLabels: {
              color: "#374151",
              font: { size: 12, weight: "500" },
              padding: 12
            }
          }
        }
      }
    })
  }

  disconnect() {
    if (this.chart) this.chart.destroy()
  }
}

/**
 * DownloadJson hook
 *
 * Listens for a "download_json" push event from the server and triggers a
 * client-side file download using a data URI. No server route is needed.
 *
 * Expected payload: { filename: string, content: string }
 */
const DownloadJsonHook = {
  mounted() {
    this.handleEvent("download_json", ({filename, content}) => {
      const encoded = encodeURIComponent(content)
      const a = document.createElement("a")
      a.href = `data:application/json;charset=utf-8,${encoded}`
      a.download = filename
      a.style.display = "none"
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
    })
  }
}

export {DownloadJsonHook}

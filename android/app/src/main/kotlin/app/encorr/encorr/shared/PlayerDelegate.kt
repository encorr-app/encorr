package app.encorr.encorr.shared

interface PlayerDelegate {
  fun onPropertyChange(name: String, value: Any?)
  fun onEvent(name: String, data: Map<String, Any>?)
}

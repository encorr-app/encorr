package com.edde746.plezy.inline

import android.app.Activity
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Second lightweight MPV instance for inline/background trailers. Renders into a
 * Flutter Texture via [MpvTexturePlayerCore], independent of the singleton
 * full-screen players on `com.plezy/exo_player` and `com.plezy/mpv_player`.
 */
class InlinePlayerPlugin :
  FlutterPlugin,
  MethodChannel.MethodCallHandler,
  EventChannel.StreamHandler,
  ActivityAware,
  com.edde746.plezy.shared.PlayerDelegate {

  companion object {
    private const val TAG = "InlinePlayerPlugin"
    private const val METHOD_CHANNEL = "com.plezy/inline_player"
    private const val EVENT_CHANNEL = "com.plezy/inline_player/events"
  }

  private lateinit var methodChannel: MethodChannel
  private lateinit var eventChannel: EventChannel
  private var eventSink: EventChannel.EventSink? = null
  private var textureRegistry: TextureRegistry? = null
  private var playerCore: MpvTexturePlayerCore? = null
  private var activity: Activity? = null
  private val nameToId = mutableMapOf<String, Int>()
  private var sessionGeneration = 0

  private val pendingInitResults = mutableListOf<MethodChannel.Result>()
  @Volatile private var isInitializing = false

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    textureRegistry = binding.textureRegistry
    methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
    methodChannel.setMethodCallHandler(this)
    eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
    eventChannel.setStreamHandler(this)
    Log.d(TAG, "Attached to engine")
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    textureRegistry = null
    Log.d(TAG, "Detached from engine")
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    Log.d(TAG, "Attached to activity")
  }

  override fun onDetachedFromActivity() {
    ++sessionGeneration
    playerCore?.dispose()
    playerCore = null
    completePendingInits(textureId = null, errorMessage = "Activity detached")
    activity = null
    Log.d(TAG, "Detached from activity")
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "initialize" -> handleInitialize(result)
      "dispose" -> handleDispose(result)
      "setProperty" -> handleSetProperty(call, result)
      "getProperty" -> handleGetProperty(call, result)
      "observeProperty" -> handleObserveProperty(call, result)
      "command" -> handleCommand(call, result)
      "updateFrame" -> handleUpdateFrame(result)
      "isInitialized" -> result.success(playerCore?.isInitialized ?: false)
      "setLogLevel" -> result.success(null)
      else -> result.notImplemented()
    }
  }

  private fun handleInitialize(result: MethodChannel.Result) {
    val currentActivity = activity
    val registry = textureRegistry
    if (currentActivity == null || registry == null) {
      result.error("NO_ACTIVITY", "Activity or texture registry not available", null)
      return
    }

    val core = playerCore
    if (core?.isInitialized == true && core.textureId != 0L) {
      result.success(core.textureId)
      return
    }

    synchronized(pendingInitResults) {
      pendingInitResults += result
      if (isInitializing) return
      isInitializing = true
    }

    currentActivity.runOnUiThread {
      val gen: Int
      val newCore: MpvTexturePlayerCore
      try {
        if (playerCore != null && playerCore?.isInitialized != true) {
          playerCore?.dispose()
          playerCore = null
        }

        gen = ++sessionGeneration
        newCore = MpvTexturePlayerCore(currentActivity, registry).apply {
          delegate = this@InlinePlayerPlugin
        }
        playerCore = newCore
      } catch (e: Exception) {
        Log.e(TAG, "Failed to create inline player core", e)
        completePendingInits(textureId = null, errorMessage = e.message)
        return@runOnUiThread
      }

      newCore.initialize { textureId ->
        val stale = gen != sessionGeneration || playerCore !== newCore
        if (stale) {
          Log.d(TAG, "Stale inline init callback (gen=$gen)")
        }
        completePendingInits(textureId = if (stale) null else textureId)
      }
    }
  }

  private fun completePendingInits(textureId: Long?, errorMessage: String? = null) {
    val pending = synchronized(pendingInitResults) {
      isInitializing = false
      val copy = pendingInitResults.toList()
      pendingInitResults.clear()
      copy
    }
    for (r in pending) {
      when {
        errorMessage != null -> r.error("INIT_FAILED", errorMessage, null)
        textureId != null -> r.success(textureId)
        else -> r.error("INIT_FAILED", "Inline player initialization failed", null)
      }
    }
  }

  private fun handleDispose(result: MethodChannel.Result) {
    activity?.runOnUiThread {
      val core = playerCore
      ++sessionGeneration
      playerCore = null
      completePendingInits(textureId = null, errorMessage = "Disposed during init")
      core?.dispose {
        Log.d(TAG, "Disposed")
        result.success(null)
      } ?: result.success(null)
    } ?: result.success(null)
  }

  private fun handleSetProperty(call: MethodCall, result: MethodChannel.Result) {
    val name = call.argument<String>("name")
    val value = call.argument<String>("value")
    if (name == null || value == null) {
      result.error("INVALID_ARGS", "Missing 'name' or 'value'", null)
      return
    }
    playerCore?.setProperty(name, value)
    result.success(null)
  }

  private fun handleGetProperty(call: MethodCall, result: MethodChannel.Result) {
    val name = call.argument<String>("name")
    if (name == null) {
      result.error("INVALID_ARGS", "Missing 'name'", null)
      return
    }
    result.success(playerCore?.getProperty(name))
  }

  private fun handleObserveProperty(call: MethodCall, result: MethodChannel.Result) {
    val name = call.argument<String>("name")
    val format = call.argument<String>("format")
    val id = call.argument<Int>("id")
    if (name == null || format == null || id == null) {
      result.error("INVALID_ARGS", "Missing 'name', 'format', or 'id'", null)
      return
    }
    nameToId[name] = id
    playerCore?.observeProperty(name, format)
    result.success(null)
  }

  private fun handleCommand(call: MethodCall, result: MethodChannel.Result) {
    val args = call.argument<List<String>>("args")
    if (args == null) {
      result.error("INVALID_ARGS", "Missing 'args'", null)
      return
    }
    val core = playerCore
    if (core == null) {
      result.success(null)
      return
    }
    core.command(args.toTypedArray()) {
      result.success(null)
    }
  }

  private fun handleUpdateFrame(result: MethodChannel.Result) {
    playerCore?.updateFrame()
    result.success(null)
  }

  override fun onPropertyChange(name: String, value: Any?) {
    val propId = nameToId[name] ?: return
    eventSink?.success(listOf(propId, value))
  }

  override fun onEvent(name: String, data: Map<String, Any>?) {
    val event = mutableMapOf<String, Any>(
      "type" to "event",
      "name" to name
    )
    data?.let { event["data"] = it }
    eventSink?.success(event)
  }
}

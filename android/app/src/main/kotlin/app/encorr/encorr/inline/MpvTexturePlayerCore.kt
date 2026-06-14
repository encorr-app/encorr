package app.encorr.encorr.inline

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import app.encorr.encorr.shared.PlayerDelegate
import dev.jdtech.mpv.*
import io.flutter.view.TextureRegistry
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Lightweight MPV core that renders into a Flutter [TextureRegistry.SurfaceProducer]
 * instead of a full-window [android.view.SurfaceView]. Used for muted background
 * trailers on detail pages alongside the main full-screen player.
 */
class MpvTexturePlayerCore(
  private val activity: Activity,
  private val textureRegistry: TextureRegistry,
) {
  companion object {
    private const val TAG = "MpvTexturePlayerCore"
    private const val DEFAULT_TEXTURE_WIDTH = 1280
    private const val DEFAULT_TEXTURE_HEIGHT = 720
  }

  var delegate: PlayerDelegate? = null
  var isInitialized: Boolean = false
    private set

  val textureId: Long
    get() = textureIdValue

  private var surfaceProducer: TextureRegistry.SurfaceProducer? = null
  private var textureIdValue: Long = 0L

  @Volatile private var disposing: Boolean = false
  @Volatile private var player: MpvPlayer? = null
  @Volatile private var cachedPaused: Boolean = true
  @Volatile private var hasAttachedSurface: Boolean = false

  private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
  private val handler = Handler(Looper.getMainLooper())
  private val videoOutputMutex = Mutex()

  private val surfaceCallback = object : TextureRegistry.SurfaceProducer.Callback {
    override fun onSurfaceAvailable() {
      Log.d(TAG, "Surface available")
      attachSurface("onSurfaceAvailable")
    }

    override fun onSurfaceCleanup() {
      Log.d(TAG, "Surface cleanup")
      detachSurface("onSurfaceCleanup")
    }
  }

  fun initialize(onResult: (Long?) -> Unit) {
    if (isInitialized && textureIdValue != 0L) {
      onResult(textureIdValue)
      return
    }

    try {
      disposing = false
      cachedPaused = true
      hasAttachedSurface = false

      val producer = textureRegistry.createSurfaceProducer(TextureRegistry.SurfaceLifecycle.manual)
      producer.setSize(DEFAULT_TEXTURE_WIDTH, DEFAULT_TEXTURE_HEIGHT)
      producer.setCallback(surfaceCallback)
      surfaceProducer = producer
      textureIdValue = producer.id()

      setupFrameListener(producer)

      scope.launch {
        try {
          if (disposing) {
            onResult(null)
            return@launch
          }

          val displayFpsOverride = currentDisplayFpsOverride()
          val p = MpvPlayer.create(activity.applicationContext) {
            setOption("vo", "gpu")
            setOption("gpu-context", "android")
            setOption("opengl-es", "yes")
            setOption("keep-open", "yes")
            setOption("loop-file", "inf")
            setOption("ao", "audiotrack,opensles")
            if (displayFpsOverride != null) {
              setOption("display-fps-override", displayFpsOverride)
            }
          }

          if (disposing) {
            p.close()
            onResult(null)
            return@launch
          }

          player = p
          isInitialized = true

          attachSurface("initialize")
          collectEvents(p)
          collectPropertyChanges(p)
          collectLogMessages(p)

          Log.d(TAG, "Initialized texture player id=$textureIdValue")
          onResult(textureIdValue)
        } catch (e: Exception) {
          Log.e(TAG, "Failed to initialize MPV texture player", e)
          onResult(null)
        }
      }
    } catch (e: Exception) {
      Log.e(TAG, "Failed to create texture surface", e)
      onResult(null)
    }
  }

  private fun setupFrameListener(producer: TextureRegistry.SurfaceProducer) {
    if (producer is TextureRegistry.GLTextureConsumer) {
      producer.surfaceTexture.setOnFrameAvailableListener { surfaceTexture ->
        handler.post {
          if (!disposing) {
            surfaceProducer?.scheduleFrame()
          }
        }
      }
    }
  }

  private fun scheduleTextureFrame() {
    if (disposing || cachedPaused) return
    surfaceProducer?.scheduleFrame()
  }

  private fun currentDisplayFpsOverride(): String? {
    val refreshRate = activity.display?.mode?.refreshRate ?: return null
    if (refreshRate <= 0f) return null
    return refreshRate.toString()
  }

  private fun collectEvents(p: MpvPlayer) {
    scope.launch(start = CoroutineStart.UNDISPATCHED) {
      p.eventFlow.collect { event ->
        when (event) {
          is MpvEvent.EndFile -> {
            val data = event.reason?.let { mapOf("reason" to it.id) }
            delegate?.onEvent("end-file", data)
          }
          is MpvEvent.FileLoaded -> delegate?.onEvent("file-loaded", null)
          is MpvEvent.PlaybackRestart -> {
            scheduleTextureFrame()
            delegate?.onEvent("playback-restart", null)
          }
          else -> {}
        }
      }
    }
  }

  private fun collectPropertyChanges(p: MpvPlayer) {
    scope.launch(start = CoroutineStart.UNDISPATCHED) {
      p.propertyFlow.collect { change ->
        if (change is PropertyChange.None) return@collect
        val value: Any? = when (change) {
          is PropertyChange.Flag -> change.value
          is PropertyChange.Int64 -> change.value
          is PropertyChange.Double -> change.value
          is PropertyChange.Str -> change.value
          is PropertyChange.None -> null
        }
        if (change.name == "pause" && change is PropertyChange.Flag) {
          cachedPaused = change.value
        }
        if (change.name == "time-pos" && !cachedPaused) {
          scheduleTextureFrame()
        }
        delegate?.onPropertyChange(change.name, value)
      }
    }
  }

  private fun collectLogMessages(p: MpvPlayer) {
    scope.launch(start = CoroutineStart.UNDISPATCHED) {
      p.logFlow.collect { msg ->
        delegate?.onEvent(
          "log-message",
          mapOf(
            "prefix" to msg.prefix,
            "level" to msg.level.name.lowercase(),
            "text" to msg.text
          )
        )
      }
    }
  }

  private fun attachSurface(reason: String) {
    val p = player
    val producer = surfaceProducer
    if (p == null || producer == null || disposing) return

    val surface = producer.surface
    if (surface == null || !surface.isValid) {
      Log.d(TAG, "attachSurface($reason): no valid surface")
      return
    }

    scope.launch(Dispatchers.IO) {
      try {
        videoOutputMutex.withLock {
          if (disposing) return@withLock
          p.attachSurface(surface)
          hasAttachedSurface = true
          val w = producer.width
          val h = producer.height
          if (w > 0 && h > 0) {
            p.setProperty("android-surface-size", "${w}x$h")
          }
          Log.d(TAG, "Attached texture surface ($reason, ${w}x$h)")
        }
      } catch (e: Exception) {
        Log.w(TAG, "Failed to attach texture surface ($reason)", e)
      }
    }
  }

  private fun detachSurface(reason: String) {
    hasAttachedSurface = false
    val p = player
    if (p == null || disposing) return

    scope.launch(Dispatchers.IO) {
      try {
        videoOutputMutex.withLock {
          if (disposing) return@withLock
          p.detachSurface()
          Log.d(TAG, "Detached texture surface ($reason)")
        }
      } catch (e: Exception) {
        Log.w(TAG, "Failed to detach texture surface ($reason)", e)
      }
    }
  }

  fun setProperty(name: String, value: String) {
    if (!isInitialized || disposing) return
    if (name == "pause") {
      cachedPaused = when (value.lowercase()) {
        "yes", "true", "1" -> true
        else -> false
      }
    }
    scope.launch {
      try {
        player?.setProperty(name, value)
      } catch (e: Exception) {
        Log.w(TAG, "setProperty($name) failed", e)
      }
    }
  }

  fun getProperty(name: String): String? {
    if (!isInitialized || disposing) return null
    return try {
      runBlocking(Dispatchers.IO) { player?.getString(name) }
    } catch (e: Exception) {
      null
    }
  }

  fun observeProperty(name: String, format: String) {
    val p = player ?: return
    if (!isInitialized) return
    val fmt = when (format) {
      "double" -> PropertyFormat.Double
      "flag" -> PropertyFormat.Flag
      "string" -> PropertyFormat.String
      else -> PropertyFormat.None
    }
    p.observeProperty(name, fmt)
  }

  fun command(args: Array<String>, onComplete: ((Boolean) -> Unit)? = null) {
    if (!isInitialized || disposing || args.isEmpty() || !scope.isActive) {
      onComplete?.invoke(false)
      return
    }
    scope.launch {
      var success = false
      try {
        player?.command(*args)
        success = true
      } catch (e: Exception) {
        Log.w(TAG, "command failed", e)
      } finally {
        onComplete?.invoke(success)
      }
    }
  }

  fun updateFrame() {
    scheduleTextureFrame()
  }

  fun dispose(onComplete: (() -> Unit)? = null) {
    if (disposing) {
      onComplete?.invoke()
      return
    }
    disposing = true
    check(Looper.myLooper() == Looper.getMainLooper())

    handler.removeCallbacksAndMessages(null)
    scope.cancel()

    val p = player
    val producer = surfaceProducer
    surfaceProducer = null
    player = null
    isInitialized = false
    hasAttachedSurface = false
    textureIdValue = 0L

    producer?.setCallback(null)
    producer?.release()

    if (p != null) {
      Thread {
        try {
          runBlocking {
            p.setProperty("force-window", "no")
            p.setProperty("vo", "null")
          }
          p.detachSurface()
          p.close()
        } catch (e: Exception) {
          Log.w(TAG, "MPV texture player close failed", e)
        }
        handler.post { onComplete?.invoke() }
      }.start()
    } else {
      onComplete?.invoke()
    }

    scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
  }
}

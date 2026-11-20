package com.omixsystems.pulsechat

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.*
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayInputStream

/** Isolated, non-navigable runtime for the same audited bundle as the web app. */
class CryptoRuntime(context: Context) {
    private val origin = "https://crypto.invalid/"
    private val main = Handler(Looper.getMainLooper())
    private val web = WebView(context)
    private val pending = mutableMapOf<Int, MethodChannel.Result>()
    private val waiting = mutableListOf<() -> Unit>()
    private var next = 0
    private var ready = false
    init {
        web.settings.apply {
            javaScriptEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            blockNetworkLoads = true
            cacheMode = WebSettings.LOAD_NO_CACHE
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest) = true
            override fun shouldInterceptRequest(v: WebView, r: WebResourceRequest): WebResourceResponse {
                val name = r.url.toString().removePrefix(origin)
                if (r.url.toString() == origin + name && name in setOf("index.html", "openpgp.min.js", "bridge.js")) {
                    return WebResourceResponse(if (name.endsWith(".js")) "application/javascript" else "text/html", "UTF-8",
                        context.assets.open("flutter_assets/assets/crypto/$name"))
                }
                return WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(byteArrayOf()))
            }
            override fun onPageFinished(v: WebView, url: String) {
                if (url != origin + "index.html") return
                ready = true
                waiting.toList().forEach { it() }; waiting.clear()
            }
        }
        web.addJavascriptInterface(object {
            @JavascriptInterface fun complete(id: Int, ok: Boolean, value: String) {
                main.post { pending.remove(id)?.let { if (ok) it.success(value) else it.error("CRYPTO", "Cryptographic operation failed", null) } }
            }
        }, "BroResult")
        web.loadUrl(origin + "index.html")
    }
    fun run(input: String, result: MethodChannel.Result) {
        val id = ++next
        pending[id] = result
        val execute = {
            if (pending.containsKey(id)) web.evaluateJavascript("Promise.resolve().then(()=>broCrypto(${JSONObject.quote(input)})).then(v=>BroResult.complete($id,true,v),()=>BroResult.complete($id,false,''));void 0", null)
        }
        if (ready) execute() else waiting.add(execute)
        main.postDelayed({ pending.remove(id)?.error("TIMEOUT", "Cryptographic operation timed out", null) }, 30000)
    }
    fun close() {
        waiting.clear(); main.removeCallbacksAndMessages(null)
        pending.values.forEach { it.error("CLOSED", "Runtime stopped", null) }; pending.clear()
        web.removeJavascriptInterface("BroResult"); web.destroy()
    }
}

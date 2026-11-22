package app.climabit

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Localização aproximada usando só o Android (sem Google Play Services).
 * A posição é devolvida ao app e não é guardada nem enviada para fora do aparelho.
 */
class MainActivity : FlutterActivity() {
    private var pendente: MethodChannel.Result? = null
    private val codigoPermissao = 7

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tempo_oficial/localizacao")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "obter" -> obter(result)
                    else -> result.notImplemented()
                }
            }
        Atualizacao.registrar(flutterEngine.dartExecutor.binaryMessenger, this)
        // Abre a tela do app nas configurações do Android (bateria, notificações).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tempo_oficial/sistema")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "abrirDetalhesDoApp" -> {
                        val i = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.fromParts("package", packageName, null),
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        result.success(runCatching { startActivity(i) }.isSuccess)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun temPermissao() =
        checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun obter(result: MethodChannel.Result) {
        if (temPermissao()) {
            buscar(result)
            return
        }
        pendente?.error("cancelada", "Novo pedido de localização", null)
        pendente = result
        requestPermissions(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION), codigoPermissao)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != codigoPermissao) return
        val r = pendente ?: return
        pendente = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            buscar(r)
        } else {
            r.error("negada", "Permissão de localização negada", null)
        }
    }

    @Suppress("MissingPermission")
    private fun buscar(result: MethodChannel.Result) {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val provedores = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(LocationManager.FUSED_PROVIDER)
            add(LocationManager.NETWORK_PROVIDER)
            add(LocationManager.GPS_PROVIDER)
            add(LocationManager.PASSIVE_PROVIDER)
        }.filter { runCatching { lm.isProviderEnabled(it) }.getOrDefault(false) }

        if (provedores.isEmpty()) {
            result.error("desligada", "A localização do aparelho está desligada", null)
            return
        }

        // Posição recente já conhecida pelo aparelho (até 30 minutos).
        val recente = provedores
            .mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }
            .filter { System.currentTimeMillis() - it.time < 30 * 60 * 1000 }
            .maxByOrNull { it.time }
        if (recente != null) {
            result.success(mapa(recente))
            return
        }

        var respondido = false
        val responder: (Location?) -> Unit = { loc ->
            if (!respondido) {
                respondido = true
                if (loc != null) result.success(mapa(loc))
                else result.error("sem_sinal", "Não foi possível obter a localização", null)
            }
        }
        // Tenta um provedor por vez (rede primeiro; GPS se a rede não responder em 10 s).
        val fila = provedores.filter { it != LocationManager.PASSIVE_PROVIDER }
        if (fila.isEmpty()) {
            result.error("desligada", "A localização do aparelho está desligada", null)
            return
        }
        tentar(lm, fila, 0) { responder(it) }
    }

    @Suppress("MissingPermission")
    private fun tentar(
        lm: LocationManager,
        fila: List<String>,
        i: Int,
        fim: (Location?) -> Unit,
    ) {
        if (i >= fila.size) {
            fim(null)
            return
        }
        val principal = Handler(Looper.getMainLooper())
        var terminou = false
        val proximo = {
            if (!terminou) {
                terminou = true
                tentar(lm, fila, i + 1, fim)
            }
        }
        val recebeu: (Location?) -> Unit = { loc ->
            if (!terminou) {
                if (loc != null) {
                    terminou = true
                    fim(loc)
                } else {
                    proximo()
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val cancelar = CancellationSignal()
            lm.getCurrentLocation(fila[i], cancelar, mainExecutor) { recebeu(it) }
            principal.postDelayed({
                if (!terminou) cancelar.cancel()
                proximo()
            }, 10_000)
        } else {
            val ouvinte = android.location.LocationListener { recebeu(it) }
            @Suppress("DEPRECATION")
            lm.requestSingleUpdate(fila[i], ouvinte, Looper.getMainLooper())
            principal.postDelayed({
                if (!terminou) lm.removeUpdates(ouvinte)
                proximo()
            }, 10_000)
        }
    }

    private fun mapa(l: Location) = mapOf("lat" to l.latitude, "lon" to l.longitude)
}

package app.climabit

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Entrega o APK baixado ao instalador do Android (classe própria para não colidir com
 *  o FileProvider de outras bibliotecas no manifesto). */
class ArquivosAtualizacao : FileProvider()

/**
 * Atualização do app a partir do GitHub: o Dart baixa o APK para a pasta de cache e
 * pede aqui para abrir o instalador. O Android confere se a assinatura é a mesma do app
 * instalado; se não for, recusa a atualização.
 */
object Atualizacao {
    fun registrar(messenger: BinaryMessenger, activity: Activity) {
        MethodChannel(messenger, "tempo_oficial/atualizacao").setMethodCallHandler { call, result ->
            when (call.method) {
                "pasta" -> {
                    val pasta = File(activity.cacheDir, "atualizacao")
                    pasta.mkdirs()
                    // Apaga APKs antigos baixados antes.
                    pasta.listFiles()?.forEach { it.delete() }
                    result.success(pasta.absolutePath)
                }
                // O APK publicado é só para processadores de 64 bits (arm64-v8a).
                "suporta64" -> result.success(Build.SUPPORTED_ABIS.contains("arm64-v8a"))
                "podeInstalar" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        activity.packageManager.canRequestPackageInstalls()
                )
                "pedirPermissao" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        activity.startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}"),
                            )
                        )
                    }
                    result.success(null)
                }
                "instalar" -> {
                    val caminho = call.argument<String>("caminho")
                    if (caminho == null) {
                        result.error("sem_arquivo", "Caminho do APK ausente", null)
                    } else {
                        try {
                            val uri = FileProvider.getUriForFile(
                                activity, "${activity.packageName}.atualizacao", File(caminho),
                            )
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK
                                )
                            activity.startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("falhou", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

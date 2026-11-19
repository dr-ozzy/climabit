package app.climabit

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Widgets do ClimaBit na tela inicial do celular. Os textos chegam prontos do app
 * (lib/dados/widget_tela.dart); aqui só se escolhe a imagem de fundo e a faixa de alerta.
 */
private fun preencher(
    context: Context,
    gerenciador: AppWidgetManager,
    ids: IntArray,
    dados: SharedPreferences,
    layout: Int,
    prefixoFundo: String?,
    campos: Set<Int>,
    chaveAlerta: String = "texto_alerta",
) {
    for (id in ids) {
        val v = RemoteViews(context.packageName, layout)
        val temperatura = dados.getString("temperatura", null)

        v.setTextViewText(R.id.temperatura, temperatura ?: "--°")
        // Cada tamanho de widget tem só alguns campos (os outros não existem no layout).
        val textos = mapOf(
            R.id.ceu to if (temperatura == null) "Abra o app" else dados.getString("ceu", ""),
            R.id.max_min to dados.getString("max_min", ""),
            R.id.chuva to dados.getString("chuva", ""),
            R.id.cidade to dados.getString("cidade", ""),
            R.id.hora to dados.getString("hora", ""),
            R.id.sensacao to dados.getString("sensacao", ""),
            R.id.h1_hora to dados.getString("h1_hora", ""),
            R.id.h1_temp to dados.getString("h1_temp", ""),
            R.id.h1_sens to dados.getString("h1_sens", ""),
            R.id.h2_hora to dados.getString("h2_hora", ""),
            R.id.h2_temp to dados.getString("h2_temp", ""),
            R.id.h2_sens to dados.getString("h2_sens", ""),
            R.id.h3_hora to dados.getString("h3_hora", ""),
            R.id.h3_temp to dados.getString("h3_temp", ""),
            R.id.h3_sens to dados.getString("h3_sens", ""),
        )
        for ((campo, texto) in textos) {
            if (campo in campos) textoOpcional(v, campo, texto)
        }

        if (prefixoFundo != null) {
            // Widgets com cena em pixel art.
            val fundo = dados.getString("fundo", "parcial_dia_campo")
            var img = context.resources.getIdentifier(
                "ceu_${prefixoFundo}_$fundo", "drawable", context.packageName)
            if (img == 0) {
                img = context.resources.getIdentifier(
                    "ceu_${prefixoFundo}_parcial_dia_campo", "drawable", context.packageName)
            }
            v.setImageViewResource(R.id.fundo, img)
        } else {
            // Widgets simples: fundo translúcido e ícone do céu.
            val icone = context.resources.getIdentifier(
                "ic_tempo_${dados.getString("icone", "parcial_dia")}", "drawable",
                context.packageName)
            v.setImageViewResource(
                R.id.icone, if (icone != 0) icone else R.drawable.ic_tempo_parcial_dia)
        }

        // Barra estreita (3 colunas da tela inicial): mostra só 2 horas, para os textos caberem.
        if (R.id.h3_coluna in campos) {
            val largura = gerenciador.getAppWidgetOptions(id)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val estreita = largura in 1 until 285
            v.setViewVisibility(R.id.h3_coluna, if (estreita) View.GONE else View.VISIBLE)
            if (estreita) {
                textoOpcional(v, R.id.sensacao,
                    dados.getString("sensacao", "")?.replace("sensação", "sens."))
                // Letras um pouco menores para as 2 horas caberem (a barra larga usa o layout).
                for (campo in listOf(R.id.h1_sens, R.id.h2_sens)) {
                    v.setTextViewTextSize(campo, TypedValue.COMPLEX_UNIT_SP, 10f)
                }
                for (campo in listOf(R.id.h1_temp, R.id.h2_temp)) {
                    v.setTextViewTextSize(campo, TypedValue.COMPLEX_UNIT_SP, 18f)
                }
                v.setTextViewTextSize(R.id.sensacao, TypedValue.COMPLEX_UNIT_SP, 12f)
                v.setTextViewTextSize(R.id.cidade, TypedValue.COMPLEX_UNIT_SP, 13f)
            }
        }

        // Faixa de alerta: amarela (potencial perigo) ou vermelha (perigo, sirene).
        val nivel = lerInteiro(dados, "nivel_alerta")
        if (nivel > 0) {
            val vermelho = nivel >= 2
            v.setViewVisibility(R.id.alerta, View.VISIBLE)
            v.setInt(R.id.alerta, "setBackgroundColor",
                if (vermelho) Color.parseColor("#D32F2F") else Color.parseColor("#FFC107"))
            if (R.id.alerta_texto in campos) {
                v.setTextViewText(R.id.alerta_texto, dados.getString(chaveAlerta, null)
                    .takeUnless { it.isNullOrEmpty() } ?: dados.getString("texto_alerta", "Alerta"))
                v.setTextColor(R.id.alerta_texto,
                    if (vermelho) Color.WHITE else Color.parseColor("#1F1A00"))
            }
        } else {
            v.setViewVisibility(R.id.alerta, View.GONE)
        }

        // Toque em qualquer parte abre o app.
        v.setOnClickPendingIntent(
            R.id.raiz, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
        gerenciador.updateAppWidget(id, v)
    }
}

/** O app grava números como Long; aceita também Int ou texto. */
private fun lerInteiro(dados: SharedPreferences, chave: String): Int =
    when (val x = dados.all[chave]) {
        is Long -> x.toInt()
        is Int -> x
        is String -> x.toIntOrNull() ?: 0
        else -> 0
    }

private fun textoOpcional(v: RemoteViews, id: Int, texto: String?) {
    if (texto.isNullOrEmpty()) {
        v.setViewVisibility(id, View.GONE)
    } else {
        v.setViewVisibility(id, View.VISIBLE)
        v.setTextViewText(id, texto)
    }
}

class WidgetClima1x1 : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = preencher(context, appWidgetManager, appWidgetIds, widgetData, R.layout.widget_clima_1x1, "q",
        setOf())
}

class WidgetClima2x2 : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = preencher(context, appWidgetManager, appWidgetIds, widgetData, R.layout.widget_clima_2x2, "q",
        setOf(R.id.ceu, R.id.max_min, R.id.alerta_texto))
}

class WidgetClima4x2 : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = preencher(context, appWidgetManager, appWidgetIds, widgetData, R.layout.widget_clima_4x2, "l",
        setOf(R.id.ceu, R.id.max_min, R.id.chuva, R.id.cidade, R.id.hora, R.id.alerta_texto))
}

/** Campos da barra 4 × 1: agora e 3 horas do dia, cada uma com temperatura e sensação. */
private val camposBarra = setOf(
    R.id.cidade, R.id.sensacao, R.id.alerta_texto,
    R.id.h1_hora, R.id.h1_temp, R.id.h1_sens,
    R.id.h2_hora, R.id.h2_temp, R.id.h2_sens,
    R.id.h3_hora, R.id.h3_temp, R.id.h3_sens, R.id.h3_coluna,
)

/** Barra 4 × 1: redesenha quando a pessoa muda o tamanho do widget. */
abstract class WidgetBarra : HomeWidgetProvider() {
    override fun onAppWidgetOptionsChanged(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId),
            HomeWidgetPlugin.getData(context))
    }
}

class WidgetClima4x1 : WidgetBarra() {
    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = preencher(context, appWidgetManager, appWidgetIds, widgetData, R.layout.widget_clima_4x1, "l",
        camposBarra, "alerta_curto")
}

class WidgetSimples4x1 : WidgetBarra() {
    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = preencher(context, appWidgetManager, appWidgetIds, widgetData,
        R.layout.widget_simples_4x1, null, camposBarra, "alerta_curto")
}

class WidgetSimples1x1 : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = preencher(context, appWidgetManager, appWidgetIds, widgetData,
        R.layout.widget_simples_1x1, null, setOf())
}

class WidgetSimples2x2 : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = preencher(context, appWidgetManager, appWidgetIds, widgetData,
        R.layout.widget_simples_2x2, null, setOf(R.id.ceu, R.id.max_min, R.id.alerta_texto))
}

class WidgetSimples4x2 : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = preencher(context, appWidgetManager, appWidgetIds, widgetData,
        R.layout.widget_simples_4x2, null, setOf(R.id.ceu, R.id.max_min, R.id.chuva, R.id.cidade, R.id.hora, R.id.alerta_texto))
}

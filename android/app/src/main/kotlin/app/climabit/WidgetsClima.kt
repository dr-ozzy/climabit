package app.climabit

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.Shader
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
            R.id.detalhes to dados.getString("detalhes", ""),
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
            if (layout == R.layout.widget_cartao) {
                iconeEscurecido(context, dados.getString("icone", "parcial_dia") ?: "parcial_dia")
                    ?.let { v.setImageViewBitmap(R.id.icone, it) }
            }
        }

        // Ícone colorido do céu em cada hora da barra.
        if (R.id.h1_icone in campos) {
            for ((campo, chave) in listOf(R.id.h1_icone to "h1_icone",
                    R.id.h2_icone to "h2_icone", R.id.h3_icone to "h3_icone")) {
                val nome = dados.getString(chave, "") ?: ""
                val img = if (nome.isEmpty()) 0 else context.resources.getIdentifier(
                    "ic_tempo_$nome", "drawable", context.packageName)
                if (img == 0) {
                    v.setViewVisibility(campo, View.GONE)
                } else {
                    v.setViewVisibility(campo, View.VISIBLE)
                    v.setImageViewResource(campo, img)
                }
            }
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

        // Gráfico das próximas horas (widgets "Cartão claro" e "Horário escuro").
        if (R.id.grafico in campos) {
            val opcoes = gerenciador.getAppWidgetOptions(id)
            val largura = opcoes.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
                .takeIf { it > 0 } ?: 320
            val altura = opcoes.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
                .takeIf { it > 0 } ?: 200
            val escuro = layout == R.layout.widget_horario
            // Espaço do cabeçalho e das margens; o resto é do gráfico.
            val cabecalho = if (escuro) 78 else 108
            val grafico = desenharGrafico(context, dados, largura - 32,
                (altura - cabecalho).coerceIn(70, 260), escuro)
            if (grafico == null) {
                v.setViewVisibility(R.id.grafico, View.GONE)
            } else {
                v.setViewVisibility(R.id.grafico, View.VISIBLE)
                v.setImageViewBitmap(R.id.grafico, grafico)
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
    R.id.h1_icone, R.id.h2_icone, R.id.h3_icone,
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

/** Campos dos widgets com gráfico (cada layout tem só os seus). */
private val camposCartao = setOf(
    R.id.cidade, R.id.sensacao, R.id.max_min, R.id.detalhes, R.id.alerta_texto, R.id.grafico,
)
private val camposHorario = setOf(
    R.id.cidade, R.id.sensacao, R.id.max_min, R.id.ceu, R.id.alerta_texto, R.id.grafico,
)

/** Cartão claro: relógio, cidade, agora e gráfico de linha das próximas horas. */
class WidgetCartao : WidgetBarra() {
    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = preencher(context, appWidgetManager, appWidgetIds, widgetData, R.layout.widget_cartao,
        null, camposCartao, "alerta_curto")
}

/** Horário escuro: agora no alto e colunas por hora com a linha da temperatura. */
class WidgetHorario : WidgetBarra() {
    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) = preencher(context, appWidgetManager, appWidgetIds, widgetData, R.layout.widget_horario,
        null, camposHorario, "alerta_curto")
}

/**
 * Desenha as próximas horas: temperatura sobre uma linha, chance de chuva, ícone do céu e
 * hora. [escuro] = colunas alternadas e linha dourada preenchida; senão, linha laranja
 * suave sobre fundo claro. Quantas horas cabem depende da largura (uma a cada 44 dp).
 */
private fun desenharGrafico(
    context: Context, dados: SharedPreferences, larguraDp: Int, alturaDp: Int, escuro: Boolean,
): Bitmap? {
    val total = lerInteiro(dados, "g_n")
    if (total < 2) return null
    val n = minOf(total, maxOf(3, larguraDp / 44))
    val horas = List(n) { dados.getString("g${it}_h", "") ?: "" }
    val temps = List(n) { (dados.getString("g${it}_t", "") ?: "").toIntOrNull() }
    val chances = List(n) { dados.getString("g${it}_p", "") ?: "" }
    val icones = List(n) { dados.getString("g${it}_i", "") ?: "" }
    val validas = temps.filterNotNull()
    if (validas.size < 2) return null

    val d = context.resources.displayMetrics.density
    val w = (larguraDp * d).toInt().coerceAtLeast(100)
    // Linha baixa e suave, como nos exemplos: no máximo ~50 dp de altura para a linha;
    // o espaço que sobra no widget fica vazio (a imagem fica centralizada).
    val h = (minOf(alturaDp, if (escuro) 190 else 150) * d).toInt().coerceAtLeast(60)
    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val c = Canvas(bmp)
    val col = w.toFloat() / n

    val corTexto = if (escuro) Color.WHITE else Color.parseColor("#1B1D21")
    val corSuave = if (escuro) Color.parseColor("#AEB6C2") else Color.parseColor("#5A5E66")
    val corChuva = if (escuro) Color.parseColor("#7FB8FF") else Color.parseColor("#2F6FB3")
    val corLinha = if (escuro) Color.parseColor("#E8B04A") else Color.parseColor("#F08A4B")
    fun pincel(cor: Int, sp: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = cor; textSize = sp * d; textAlign = Paint.Align.CENTER
    }
    val pTemp = pincel(corTexto, 13f)
    val pHora = pincel(corSuave, 12f)
    val pChuva = pincel(corChuva, 11f)

    // De baixo para cima: hora, ícone, chance de chuva; o resto é a área da linha.
    val yHora = h - 3 * d
    val icone = 22 * d
    val topoIcone = yHora - pHora.textSize - 3 * d - icone
    val yChuva = topoIcone - 3 * d
    val baseLinha = yChuva - pChuva.textSize - 6 * d
    val topoLinha = pTemp.textSize + 6 * d
    val min = validas.minOrNull()!!
    val max = validas.maxOrNull()!!
    val faixa = maxOf(8, max - min).toFloat()
    fun yDe(t: Int) = baseLinha - (t - min) / faixa * (baseLinha - topoLinha)

    if (escuro) {
        // Colunas alternadas, do alto até as horas.
        val pCol = Paint().apply { color = Color.parseColor("#14FFFFFF") }
        for (i in 0 until n step 2) {
            c.drawRect(i * col + 2 * d, 0f, (i + 1) * col - 2 * d, h.toFloat(), pCol)
        }
    }

    // Linha: suave (curvas) entre os centros das colunas.
    val pontos = (0 until n).mapNotNull { i -> temps[i]?.let { (i + 0.5f) * col to yDe(it) } }
    val linha = Path()
    pontos.forEachIndexed { k, (x, y) ->
        if (k == 0) linha.moveTo(x, y) else {
            val (x0, y0) = pontos[k - 1]
            val meio = (x0 + x) / 2
            linha.cubicTo(meio, y0, meio, y, x, y)
        }
    }
    if (escuro) {
        val area = Path(linha).apply {
            lineTo(pontos.last().first, baseLinha + 4 * d)
            lineTo(pontos.first().first, baseLinha + 4 * d)
            close()
        }
        c.drawPath(area, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(0f, topoLinha, 0f, baseLinha + 4 * d,
                Color.argb(110, 232, 176, 74), Color.argb(10, 232, 176, 74), Shader.TileMode.CLAMP)
        })
    }
    c.drawPath(linha, Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = corLinha; style = Paint.Style.STROKE; strokeWidth = 2.2f * d
        strokeCap = Paint.Cap.ROUND
    })
    if (escuro) {
        val pPonto = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = corLinha }
        for ((x, y) in pontos) c.drawCircle(x, y, 2.6f * d, pPonto)
    }

    for (i in 0 until n) {
        val x = (i + 0.5f) * col
        temps[i]?.let { c.drawText("$it°", x, yDe(it) - 6 * d, pTemp) }
        if (chances[i].isNotEmpty()) c.drawText(chances[i], x, yChuva, pChuva)
        val idIcone = if (icones[i].isEmpty()) 0 else context.resources.getIdentifier(
            "ic_tempo_${icones[i]}", "drawable", context.packageName)
        if (idIcone != 0) {
            context.getDrawable(idIcone)?.mutate()?.let {
                if (!escuro && icones[i] != "sol" && icones[i] != "lua") it.colorFilter = filtroClaro
                it.setBounds((x - icone / 2).toInt(), topoIcone.toInt(),
                    (x + icone / 2).toInt(), (topoIcone + icone).toInt())
                it.draw(c)
            }
        }
        c.drawText(horas[i], x, yHora, pHora)
    }
    return bmp
}

/** Escurece os ícones (feitos para fundo escuro) para aparecerem no cartão branco. */
private val filtroClaro = PorterDuffColorFilter(Color.parseColor("#8E99A6"), PorterDuff.Mode.MULTIPLY)

/** Ícone do céu já escurecido, para o cartão claro. */
private fun iconeEscurecido(context: Context, nome: String): Bitmap? {
    val id = context.resources.getIdentifier("ic_tempo_$nome", "drawable", context.packageName)
    if (id == 0) return null
    val lado = (40 * context.resources.displayMetrics.density).toInt()
    val bmp = Bitmap.createBitmap(lado, lado, Bitmap.Config.ARGB_8888)
    context.getDrawable(id)?.mutate()?.apply {
        // O sol e a lua ficam como estão; nuvens e chuva ganham cinza para aparecer.
        if (nome != "sol" && nome != "lua") colorFilter = filtroClaro
        setBounds(0, 0, lado, lado)
        draw(Canvas(bmp))
    } ?: return null
    return bmp
}

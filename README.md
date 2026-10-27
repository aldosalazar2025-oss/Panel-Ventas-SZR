# Panel SZR Ventas (Windows)

Punto de venta e inventario para PC: venta por unidad o kilos, lector de código de
barras USB (escribe en el buscador y Enter), variantes, tamaños y extras, descuentos,
historial, tickets, WhatsApp, respaldos Excel/ZIP, códigos de barras e impresión
en impresoras instaladas en Windows.

## Primera vez
```
flutter pub get
flutter run -d windows
```
Programa final: `flutter build windows --release`
(`build\windows\x64\runner\Release\panel_szr_ventas.exe`).

## Pasar los datos del panel anterior
Panel anterior → Respaldos → *Crear respaldo para la web*. En este programa:
Ajustes → Configuración avanzada → *Subir respaldo* y elige ese .json.

## Ajustes → Web y App
- *Crear respaldo para la web*: archivo para la web de la tienda o para "Subir respaldo" de la app.
- *Importar ventas de la app*: en la app, Configuración avanzada → *Enviar ventas al panel*;
  aquí se agregan al historial y se descuenta el stock (sin duplicar).

## Impresora
Ajustes → Impresora: elige una impresora instalada en Windows (USB/red) o una
térmica **Bluetooth** emparejada (aparece como puerto COM y imprime directo).
Elige 58 u 80 mm según tu rollo.

Los datos se guardan en la carpeta de datos del usuario, fuera del proyecto.



# 🛒 PANEL SZR VENTAS

### Sistema de gestión de ventas para PC

Aplicación de escritorio para facilitar la administración y el control de ventas desde una computadora con Windows.

## 📥 Descargar programa

### 💻 Windows

[⬇️ DESCARGAR PANEL SZR VENTAS (.EXE)](https://github.com/aldosalazar2025-oss/Panel-Ventas-SZR/releases/download/1.1.1/Panel.Ventas.SZR.exe)

**Versión:** 1.1.1  
**Tamaño:** 15.3 MB  
**Plataforma:** Windows PC

## 🚀 Instalación

1. Haz clic en el enlace de descarga.
2. Espera a que se descargue `Panel.Ventas.SZR.exe`.
3. Abre el archivo descargado.
4. Sigue las instrucciones que aparezcan en pantalla.

## 📋 Información del proyecto

- **Nombre:** PANEL SZR VENTAS
- **Sistema operativo:** Windows
- **Formato:** `.exe`


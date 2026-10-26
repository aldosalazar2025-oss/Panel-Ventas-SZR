# Sincronización por Wi-Fi (PC ⇄ Android)

La PC es la principal. El celular guarda una copia local y le envía sus ventas.
Funciona dentro de la misma red Wi-Fi, sin Internet ni nube.

## Uso en la PC (Ajustes → Sincronización)
1. **Iniciar conexión**: muestra la IP, el puerto (8765) y un código de 6 cifras.
   La primera vez Windows pregunta por el Firewall: permite el acceso en **redes privadas**.
2. En el celular: Ajustes → Sincronización → escribe IP y código → **Conectar con la PC**.
3. Botones de la PC: **Sincronizar productos**, **Recibir ventas de Android**,
   **Sincronizar todo** (le piden la acción al celular, que la hace en unos segundos),
   **Ver estado de sincronización** (dispositivos, última sincronización, avisos de inventario)
   y **Detener conexión** (no borra nada).

## Reglas de inventario
- Las ventas del celular llevan un id único: si llegan dos veces, la segunda se ignora.
- Cada venta recibida descuenta el stock una sola vez. 10 unidades, 3 vendidas en la PC y 3 en Android = 4.
- Si el stock ya no alcanza (ambos vendieron sin conexión), la venta se guarda igual, el stock queda
  en 0 (nunca negativo) y aparece un aviso en "Ver estado" con lo pedido y lo descontado.
- Eliminar un producto en la PC es una **baja lógica**: deja de verse y venderse, el historial lo
  conserva y el celular lo retira y no lo vuelve a crear.

## Seguridad
- El secreto se deriva del código y nunca viaja por la red. Cada solicitud va firmada (HMAC-SHA256),
  con hora y nonce; se rechazan firmas inválidas, solicitudes repetidas y relojes desfasados >5 min.
- 5 códigos incorrectos bloquean el emparejamiento 1 minuto. El código cambia cada vez que inicias la conexión.
- La comunicación **no está cifrada** (HTTP local): no uses esta función en redes Wi-Fi públicas.

## Compilar
```
flutter pub get
flutter build windows --release
```

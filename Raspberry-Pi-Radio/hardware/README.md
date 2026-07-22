# Pantalla de la unidad

`tft35a.dtbo` procede del controlador `LCD35-show` de GoodTFT, usado por la
pantalla SuziePi de 3,5 pulgadas. Declara una pantalla ILI9486 de 480x320 y un
tactil ADS7846 conectados por SPI. El aprovisionador lo coloca en la particion
de arranque despues de grabar Raspberry Pi OS.

Fuente: https://github.com/goodtft/LCD-show/blob/master/usr/tft35a-overlay.dtb

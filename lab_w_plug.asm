.486p

Descr struc 	; структура для описания декскриптора сегмента
	lim 	dw 0	; Граница (биты 0..15)
	base_l 	dw 0	; База, биты 0..15
	base_m 	db 0	; База, биты 16..23
	attr_1	db 0	; Байт атрибутов 1
	attr_2	db 0	; Граница (биты 16..19) и атрибуты 2
	base_h 	db 0	; База, биты 24..31
Descr ends

Int_Descr struc	; Структура для описания декскриптора прерывания
	offs_l 	dw 0 	; Смещение в сегменте, нижняя часть
	sel		dw 0	; Селектор сегмента с обработчиком прерывания
	rezerv	db 0 	; Резерв
	attr	db 0 	; Атрибуты
	offs_h 	dw 0 	; Смещение в сегменте, верхняя часть
Int_Descr ends

PM_seg	SEGMENT PARA PUBLIC 'CODE' USE32
ASSUME	CS:PM_seg

	GDT		label	byte
	; нулевой дескриптор
	gdt_null	Descr <>

	; 32-битный 4-гигабайтный сегмент с базой = 0 для подсчёта памяти
	gdt_flatDS	Descr <0FFFFh, 0, 0, 92h, 11001111b, 0>	; 92h = 1001 0010b

	; 16-битный сегмент кода с базой RM_seg - сегмент кода реального режима
	gdt_16bitCS	Descr <RM_seg_size - 1, 0, 0, 98h, 0, 0>	; 98h = 1001 1010b

	; 32-битный сегмент кода с базой PM_seg	- сегмент кода защищённого режима
	gdt_32bitCS	Descr <PM_seg_size - 1, 0, 0, 98h, 01000000b, 0>

	; 32-битный сегмент данных с базой PM_seg - аналогично, будет использоваться для данных
	gdt_32bitDS	Descr <PM_seg_size - 1, 0, 0, 92h, 01000000b, 0>

	; 32-битный сегмент данных с базой stack_seg - сегмент стека в обоих режимах
	gdt_32bitSS	Descr <stack_len - 1, 0, 0, 92h, 01000000b, 0>

	gdt_size = $ - GDT ; размер нашей таблицы GDT + 1б (на саму метку)

	gdtr	df 0	; переменная размера 6 байт

	; Селекторы
	SEL_flatDS     equ   8
	SEL_16bitCS    equ   16
	SEL_32bitCS    equ   24
	SEL_32bitDS    equ   32
	SEL_32bitSS    equ   40

	; Таблица дескрипторов прерываний IDT
	IDT	label	byte

	; Первые 32 элемента таблицы (исключения)
	iskl Int_Descr 32 dup (<0, SEL_32bitCS, 0, 8Fh, 0>) 	; 8Fh = 1000 1111b

	; Дескриптор прерывания от таймера				
	int08 Int_Descr <0, SEL_32bitCS, 0, 8Eh, 0>		; 8Eh = 1000 1110b		

	; Дескриптор прерывания от клавиатуры
	int09 Int_Descr	<0, SEL_32bitCS, 0, 8Eh, 0>
					
	idt_size = $ - IDT							

	idtr	df 0

	; содержимое регистра IDTR в реальном режиме
	idtr_real	df 0

	Master_Mask		db 0								; Маска прерываний ведущего контроллера
	Slave_Mask		db 0								; Ведомого

	escape		db 0								; Флаг для выхода в реальный режим
	time_08		dd 0								; Счетчик тиков таймера

	; Массив для перевода скан-кода клавиатуры в ASCII-символ
	scan_ascii_arr db 49, 50, 51, 52, 53, 54, 55, 56, 57, 48, 45, 61, 8, 	 9, 	81, 87, 69, 82, 84, 89, 85, 73, 79, 80, 91, 93, 		13, 17, 65, 83, 68, 70, 71, 72, 74, 75, 76, 59, 39, 96, 		16, 92, 90, 88, 67, 86, 66, 78, 77, 44, 46, 47



	; точка входа в 32-битный защищенный режим
	PM_entry:	
		; Загрузка сегментных регистров селекторами
		mov	ax, SEL_32bitDS
		mov	ds, ax
		mov	ax, SEL_flatDS
		mov	es, ax
		mov	ax, SEL_32bitSS
		mov	ebx, stack_len
		mov	ss, ax
		mov	esp, ebx
		
		; Разрешаем прерывания
		sti
		
		; Считаем количество доступной памяти и печатаем его на экран
		call	compute_memory
		
		; Ожидание нажатия ентера (escape == 1), тогда выход в реальный режим
		enter_waiting:
			test	escape, 1
			jz	enter_waiting

		goback:			
			; Запрещаем прерывания
			cli
			
			; Переход по метке RM_return
			db	0EAh 				; Код команды far jmp
			dd	offset RM_return 	; Смещение
			dw	SEL_16bitCS 		; Селектор сегмента команд
			

	;;; Макросы ;;;
	; макрос для создания 16-тиричной цифры из числа в dl (7 -> '7', 15 -> 'F')
	num_to_char macro
	local number1

		cmp dl, 10
		jl number1
			add dl, 'A' - '0' - 10
		number1:
			add dl, '0'
	endm

	; макрос печати на экран значения регистра eax через видеобуфер
	print_from_eax macro
	local prcyc1

		push ecx
		push dx
		
		; Запишем EBP смещение на 8 символов от начала экрана + ebp
		mov ecx, 8			
		add ebp, 0B8010h 

		prcyc1:
			mov dl, al
			and dl, 0Fh	
			num_to_char 0	
			mov es:[ebp], dl	
			ror eax, 4
			sub ebp, 2
		loop prcyc1	
		
		sub ebp, 0B8010h		; возвращаем в EBP начальное значение
		pop dx
		pop ecx
	endm

	scan_to_ascii_al macro
	local pushed, leave_macro
		push ax
		push bp
		push dx

		cmp al, 80h
		jb pushed
			sub al, 80h

		pushed:
			cmp al, 1Ch
			je leave_macro

			xor ah, ah
			mov bp, ax
			mov ax, 2h
			sub bp, ax
			mov dl, scan_ascii_arr[bp] 

		mov ebp, 0B8032h
		mov es:[ebp], dl

		leave_macro:

		pop dx
		pop bp
		pop ax
	endm	
		

	;;; Обработчики прерываний ;;;	
	; Обработчик прерывания таймера
	new_int08:	
		push eax
		push ebp
		push ecx
		push dx

		mov eax, time_08

		; Печать значения счетчика таймера
		xor ebp, ebp
		print_from_eax 0
			
		; Выведем 'h' на экран
		; Запишем EBP смещение на 8 символов от начала экрана + 1 символ (h)
		mov ebp, 0B8012h
		mov dl, 'h'
		mov es:[ebp], dl
		
		inc eax
		mov time_08, eax
			
		pop dx
		pop ecx
		pop ebp
		
		; Отправляем команду End Of Interrupt ведущему контроллеру прерываний
		mov	al, 20h
		out	20h, al

		pop eax	
		
	iretd
		

	; Обработчик прерывания клавиатуры
	new_int09:
		push	eax	
	
		in	al, 60h							; прочитать код нажатой клавиши из порта клавиатуры
		
		cmp	al, 1Ch							; сравниваем с кодом ентора
		jne	not_leave						
			mov escape, 1						
		not_leave:
			scan_to_ascii_al 0

		; Отправляем команду End Of Interrupt ведущему контроллеру прерываний
		mov	al, 20h
		out	20h, al
		
		pop	eax

	iretd

	; Заглушка для исключения
	zaglush:

	iretd


	; функция подсчета доступной памяти
	compute_memory	proc
			
		push	ds
		mov	ax, SEL_flatDS
		mov	ds, ax

		mov	ebx,	100001h	; Пропускаем первый мегабайт оного сегмента
		mov	dl,		10101010b	; Контрольное значение
							
		mov ecx, 0FFF00000h	; Записываем количество оставшейся памяти (до превышения лимита в 4ГБ) - чтобы не было переполнения
		
		;в цикле считаем память
		check:
			mov	dh, ds:[ebx]	; Чтение из памяти
			mov	ds:[ebx], dl	; Загрузка в память контрольного значения
			cmp	ds:[ebx], dl	; Проверка на запись
			jnz	end_of_memory	; Если из данной ячейки вернулось не контрольное значение, то данного байта не существует, и мы дошли до конца

			mov	ds:[ebx], dh	; Если вернулось контрольное значение, то возвращаем старое значение ячейки
			inc	ebx	
		loop	check

		end_of_memory:
			pop	ds	
			xor	edx, edx
			mov	eax, ebx		; ebx содержит подсчитанное кол-во памяти, переносим его в ax
			mov	ebx, 100000h	; Переводим в Мб
			div	ebx
			
		push ebp
		push eax
		mov ebp, 20	
		print_from_eax 0	

		mov ebp, 0B8026h
		mov al, 'h'
		mov dl, al
		mov es:[ebp], dl
		add ebp, 4
		mov al, 'M'
		mov dl, al
		mov es:[ebp], dl
		add ebp, 2
		mov al, 'b'
		mov dl, al
		mov es:[ebp], dl


		pop eax
		pop ebp
				
		ret
	compute_memory	endp

	PM_seg_size = $ - GDT
PM_seg	ENDS





stack_seg	SEGMENT  PARA STACK 'STACK'
	stack_start	db	100h dup(?)
	stack_len = $ - stack_start							; длина стека для инициализации ESP
stack_seg 	ENDS





RM_seg	SEGMENT PARA PUBLIC 'CODE' USE16
ASSUME CS:RM_seg, DS:PM_seg, SS:stack_seg

	start:	
		; очистить экран
		mov	ax, 3
		int	10h
		; настроить регистр ds
		mov ax, PM_seg
		mov ds, ax
				
		; вычислить базы для всех используемых дескрипторов сегментов
		xor	eax, eax
		mov	ax, RM_seg
		shl	eax, 4	; сегменты объявлены как PARA, нужно сдвинуть на 4 бита для выравнивания по границе параграфа
		mov	word ptr gdt_16bitCS.base_l, ax 				
		shr	eax, 16
		mov	byte ptr gdt_16bitCS.base_m, al
		mov	ax, PM_seg
		shl	eax, 4
		push eax		; для вычисления адреса idt
		push eax		; для вычисления адреса gdt
		mov	word ptr GDT_32bitCS.base_l, ax 			
		mov	word ptr GDT_32bitSS.base_l, ax	
		mov	word ptr GDT_32bitDS.base_l, ax
		shr	eax, 16
		mov	byte ptr GDT_32bitCS.base_m, al
		mov	byte ptr GDT_32bitSS.base_m, al
		mov	byte ptr GDT_32bitDS.base_m, al
		
		; вычислим линейный адрес GDT
		pop eax
		add	eax, offset GDT ; Теперь в eax полный линейный адрес (адрес сегмента + смещение GDT относительно него)
		mov	dword ptr gdtr+2, eax	; кладём полный линейный адрес в младшие 4 байта переменной gdtr
		mov word ptr gdtr, gdt_size-1; в старшие 2 байта заносим размер gdt, из-за определения gdt_size (через $) настоящий размер на 1 байт меньше
		; загрузим GDT
		lgdt	fword ptr gdtr

		; аналогично вычислим линейный адрес IDT
		pop	eax
		add	eax, offset IDT
		mov	dword ptr idtr+2, eax
		mov word ptr idtr, idt_size-1
		
		; Заполним смещение в дескрипторах прерываний
		mov	eax, offset new_int08 ; прерывание таймера
		mov	int08.offs_l, ax
		shr	eax, 16
		mov	int08.offs_h, ax
		
		mov	eax, offset new_int09 ; прерывание клавиатуры
		mov	int09.offs_l, ax
		shr	eax, 16
		mov	int09.offs_h, ax

		mov cx, 32
		zaglush_loop:
			xor ebp, ebp
			mov eax, offset zaglush
			mov iskl[ebp].offs_l, ax
			shr eax, 16
			mov iskl[ebp].offs_h, ax
			add ebp, 8
		loop zaglush_loop

		;сохраним маски прерываний контроллеров
		in	al, 21h							; ведущего
		mov	Master_Mask, al	
		in	al, 0A1h						; ведомого
		mov	Slave_Mask, al
		
		;перепрограммируем ведущий контроллер 
		mov	al, 11h	
		out	20h, al	
		mov	AL, 20h	
		out	21h, al	
		mov	al, 4	
		out	21h, al							
		mov	al, 1
		out	21h, al
		; Запретим все прерывания в ведущем контроллере, кроме IRQ0 (таймер) и IRQ1(клавиатура)
		mov	al, 0FCh
		out	21h, al
		
		;запретим ВСЕ прерывания в ведомом контроллере
		mov	al, 0FFh
		out	0A1h, al

		; загрузим IDT
		lidt	fword ptr idtr
		
		; Открываем линию A20
		in	al, 92h		
		or	al, 2		
		out	92h, al	
		
		; отключить маскируемые прерывания		
		cli
		; отключить немаскируемые прерывания		
		in	al, 70h
		or	al, 80h
		out	70h, al
		
		; перейти в защищенный режим установкой соответствующего бита регистра ЦР0
		mov	eax, cr0
		or	al, 1
		mov	cr0, eax
		
		; напрямую загрузить SEL_32bitCS в регистр CS мы не можем из-за защитных ограничений
		db	66h 				; префикс изменения разрядности операндов
		db	0EAh 				; код команды far jmp
		dd	offset PM_entry 	; смещение
		dw	SEL_32bitCS 		; селектор
		; начиная с этой строчки, будет выполняться код по оффсету PM_entry
		
	RM_return:	
		; переход в реальный режим
		mov	eax, cr0
		and	al, 0FEh
		mov	cr0, eax
		
		db	0EAh
		dw	$+4
		dw	RM_seg
		
		; восстановить регистры для работы в реальном режиме
		mov	ax, PM_seg
		mov	ds, ax
		mov	es, ax
		mov	ax, stack_seg
		mov	bx, stack_len
		mov	ss, ax
		mov	sp, bx
		
		;перепрограммируем ведущий контроллер обратно на вектор 8
		mov	al, 11h	
		out	20h, al
		mov	al, 8
		out	21h, al
		mov	al, 4
		out	21h, al
		mov	al, 1
		out	21h, al

		;восстанавливаем предусмотрительно сохраненные ранее маски контроллеров прерываний
		mov	al, Master_Mask
		out	21h, al
		mov	al, Slave_Mask
		out	0A1h, al
		
		; загружаем таблицу дескрипторов прерываний реального режима	
		mov dword ptr idtr_real+2, 00000000h
		mov word ptr idtr_real, 03FFh
		lidt	fword ptr idtr_real
		
		; Закрываем А20
		in al, 92h
		and al, 0FDh
		out 92h, al

		; разрешаем немаскируемые прерывания
		in	al, 70h
		and	al, 07FH
		out	70h, al
    
    	; разрешаем маскируемые прерывания
		sti
		
		; Завершение программы
		mov	ah, 4Ch
		int	21h

	RM_seg_size = $ - start ;завершаем сегмент, указываем метку начала для сегмента
RM_seg	ENDS

END start

;	Контроллер прерывания получает сигнал о прерывании и формирует вектор прерывания, который является смещением в ТДП.
 
;	Взяв значение из регистра IDTR значение базового адреса ТДП. В нём по смещению находим 

;	дескриптор который уже и содержит селектор из ГТД, смещение и аттрибуты

;	По селектору выбираем дескриптор из ГТД, берём базовый адрес сегмента и прибавляем его к смещению
 
;	Получаем линейный адрес обработчика прерывания

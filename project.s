.equ TIMER_INTERRUPT, 0xFF202000
.equ TIMER_INTERRUPT2, 0xFF202000
.equ interrupt_time, 200000000
.equ interrupt_time2,1000000000
.equ PUSHBUTTONS, 0xFF200050
.equ LEGOCONTROLLER, 0xFF200060
.equ time_baseMotor, 1500000
.equ time_baseMotor2,11000000
.equ time_baseMotor3,99999999
.equ SEVEN_SEG_03, 0xFF200020 
.equ SEVEN_SEG_45, 0xFF200030
.equ HEXKEYPAD, 0xFF200070
.equ PASSWORD, 0xE0E0E0D0

/*
 * Fixed Registers
 * r8  - Status Register - If the machine is in stop=0/start=1 mode
 * r15 - Lego Controller
 *
 * Timers
 * Timer 1: Interrrupt to move the motors
 * Timer 2: Polling for time the motors should be on
 *
 * Motors
 * Motor 0: Base movement motor
 * Motor 1: Drill movement motor
 * Motor 2: Drill motor
 * Motor 3: Material Rotation Motor
 *
 * Pushbuttons
 * Pushbutton 1: Start buttons
 * Pushbutton 2: Stop button
 *
 */

.section .exceptions, "ax"

ISR:
	subi 	sp, sp, 16
	stw 	et, (sp)
	rdctl 	et, estatus 
	stw 	et, 4(sp)
	stw 	ea, 8(sp)
	stw 	ra, 12(sp)	
		
	#irq1 (Pushbutton) 
	rdctl 	et, ipending
	andi 	et, et, 0x2
	bne 	et, r0, InterruptPushButton
	
	#irq0 (timer) 
	rdctl 	et, ipending
	andi 	et, et, 0x1
	bne 	et, r0, InterruptTimer
	
	br 		exitInterrupt
	
InterruptPushButton:
	movia	et, PUSHBUTTONS
	ldwio 	r9, 12(et)
	movi 	r10, 0xFF
	stwio 	r10, 12(et)
	andi 	r9, r9, 0x0F					#Mask all the bits
	movi 	r10, 0x2
	beq 	r10, r9, STOP
	movi 	r10, 0x4
	beq 	r10, r9, START
	
	br 		exitInterrupt
	
STOP:
	movi 	r8, 0x0
	#Stop the interrupt timer
	movia 	et, TIMER_INTERRUPT
	movia 	r9, 0b1000
	stw		r9, 4(et)	
	
	#Stop all the motors (drill motor and material rotation motor)
	movia	r9, 0xffffffff			
	stwio 	r9, 0(r15)	
	call    setHexOFF
	call    clear_screen
	call    Machineisoff
	br 		exitInterrupt
	
START:
	
	#Start the timer interrupt

	# Checks if password is entered
	call 	setHexPIN
	call 	pollForPassword
	call 	setHexOFF
	movia 	r9, PASSWORD	
	bne 	r9, r2, exitInterrupt 

	movi 	r8, 0x1

	#Enable timer interrupts again
	movia 	et, TIMER_INTERRUPT
	movia 	r9, 0b0111
	stw		r9, 4(et)

	call    setHexON
	call    clear_screen
	call     Machineison
	call 	audio
	
InterruptTimer:
	movia 	et, TIMER_INTERRUPT
	stw 	r0, (et)  					#set timeout bit to 0
	
	#Check for start mode
	movi 	r9, 0x1
	bne 	r8, r9, exitInterrupt		#If mode not start, exit
	#addi    r22,r22,0x1
	#beq     r22,r23, STOP
	
	#move the base motor	
	movia  	r9, 0xFFFFFF0E				#enabling the motor 0, direction to forward
  	stwio  	r9, 0(r15)					#Turn on motor
	movui 	r4, %lo(time_baseMotor) 	
	movui 	r5, %hi(time_baseMotor)
	call 	timer
	movia	r9, 0xffffff0f			
	stwio 	r9, 0(r15)					#Turn off motor keeping drill and material motor on
	
firstsensor:	

	movia r9, 0xFFFFFB0F				#enable sensor 0
	stwio r9, 0(r15)
	ldwio	r10,0(r8)
	srli	r10,r10,11
	andi	r10,r10,0x1
	beq	r0,	r10,firstsensor
		
readfirstsensor:
	ldwio   r11, 0(r15)
	srli    r11, r11, 27
	andi    r11, r11, 0x0f 	
	
secondsensor:	
	movia r9, 0xFFFFEF0F			#enable sensor 1 and motor 1
	stwio r9, 0(r15)
	ldwio	r10,0(r8)
	srli	r10,r10,13
	andi	r10,r10,0x1
	bne		r0,	r10,secondsensor
	
readsecondsensor:
	ldwio   r12, 0(r15)
	srli    r12, r12, 27
	andi    r12, r12, 0x0f 	

thirdsensor:	
	movia r9, 0xFFFFBF0F				#enable sensor 2 and motor 1
	stwio r9, 0(r15)
	ldwio	r10,0(r8)
	srli	r10,r10,15
	andi	r10,r10,0x1
	bne  	r0,	r10,thirdsensor
	
readthirdsensor:
	ldwio   r13, 0(r15)
	srli    r13, r13, 27
	andi    r13, r13, 0x0f 	

	movi    r20, 0b100
	movi    r21, 0b001
	movi    r22, 0b111
	mov		r19, r0
	movi    r14, 0x7    #assuming the threshold value is 6, sensor turns on at 9 
	movi 	r19, 0x0
	blt		r11, r14, secondsen	
	movi     r19, 0b100

secondsen:
	blt 	r12, r14, thirdsen
	movi     r19, 0b010

thirdsen:
	blt     r13, r14, move
	movi     r19,  0b001

move:	
	beq r19, r20, forward
	beq r19, r21, backward
	bne r19, r22, do_nothing
	#br exitInterrupt
	
	
forward:	
	movia  	r9, 0xFFFFFB0B				#enabling the motor 1 in forward , along with sensor and motor 2 and 3
  	stwio  	r9, 0(r15)					#Turn on motor
	movui 	r4, %lo(time_baseMotor2) 	
	movui 	r5, %hi(time_baseMotor2)
	call 	timer
	movia	r9, 0xFFFFFF0F	
	stwio 	r9, 0(r15)					#Turn off motor keeping drill and material motor on	
	br 		exitInterrupt
	
backward:	
	movia  	r9, 0xFFFFFB03			  	#enabling the motor 1 in reverse, along with sensor and motor 2 and 3
  	stwio  	r9, 0(r15)					#Turn on motor
	movui 	r4, %lo(time_baseMotor2) 	
	movui 	r5, %hi(time_baseMotor2)
	call 	timer
	movia	r9, 0xFFFFFF0F		
	stwio 	r9, 0(r15)					#Turn off motor keeping drill and material motor on		

do_nothing:
	
exitInterrupt:
	ldw 	et, 4(sp)
	wrctl 	estatus, et
	ldw 	et, (sp)
	ldw 	ea, 8(sp)
	ldw 	ra, 12(sp)
	addi 	sp, sp, 16
	wrctl 	ipending,r0
	
	subi 	ea, ea, 4 					#set the return address back to account for the disturbed execution
	eret
	
.section .text
.global main

main: 
	call PrintStartingScreen
	movia 	r15, LEGOCONTROLLER
	movia 	r8,  0x0						#Set it initially to stop mode
	#movi    r22, 0x0						#set the counter
	#movi    r23, 0x10						#set the final value for counter to stop
	#Initialize the LEGO Controller
	movia  	r9, 0x07f557ff       		#Set the direction registers
	stwio 	r9, 4(r15)
	movia 	r9, 0xffffffff
	stwio 	r9, 0(r15)
	
	
	#Initialize the interrupt timer
	movia 	r9, TIMER_INTERRUPT
	movui 	r10, %lo (interrupt_time)
	stwio 	r10, 8(r9)
	movui 	r10, %hi (interrupt_time)
	stwio 	r10, 12(r9)
	stwio 	r0, 0(r9)
	
	#Start the timer with interrupt and continous enabled
	movi 	r10, 0b0111
	stwio 	r10, 4(r9)
	
	#Initialize the push buttons 1 and 2 with interrupts
	movia 	r9, PUSHBUTTONS
	movia 	r10, 0xe
	stwio 	r10, 8(r9)
	movi 	r10, 0xFF
	stwio 	r10, 12(r9)
	
	#Enable pushbuttons and interrupt timer in the IRQ Line
	movi 	r9, 0x03
	wrctl 	ctl3, r9
	
	#Set PIE bit to 1
	movi 	r9, 1
	wrctl 	ctl0, r9

	
#nothing:
#	movia  r9, 0xFFFFFFAE     	/* motor disabled */
# 	stwio  r9, 0(r15)
#	movui 	r4, %lo(time_baseMotor) 	
#	movui 	r5, %hi(time_baseMotor)
#	call 	timer
#	br firstsensor	
	call setHexOFF
	
end_loop:
	br 		end_loop		

setHexPIN:
	subi	sp, sp, 4
	stw 	ra, 0(sp)

	#Set the HEX Display to say OFF
	movia 	r9, SEVEN_SEG_45
	movia 	r10, 0x00007306 
	stwio 	r10, 0(r9)
	movia 	r9, SEVEN_SEG_03
	movia 	r10, 0x37000000 
	stwio 	r10, 0(r9)
	
	ldw 	ra, 0(sp)
	addi 	sp, sp, 4
	ret
	
setHexOFF:
	subi	sp, sp, 4
	stw 	ra, 0(sp)

	#Set the HEX Display to say OFF
	movia 	r9, SEVEN_SEG_45
	movia 	r10, 0x00003F71 
	stwio 	r10, 0(r9)
	movia 	r10, 0x71000000 
	movia   r9, SEVEN_SEG_03
	stwio 	r10, 0(r9)
	ldw 	ra, 0(sp)
	addi 	sp, sp, 4
	ret
	
setHexON:
	subi	sp, sp, 4
	stw 	ra, 0(sp)

	#Set the HEX Display to say OFF
	movia 	r9, SEVEN_SEG_45
	movia 	r10, 0x00003F37 
	stwio 	r10, 0(r9)
	movia 	r10, 0x00000000 
	movia   r9, SEVEN_SEG_03
	stwio 	r10, 0(r9)

	ldw 	ra, 0(sp)
	addi 	sp, sp, 4
	ret
	
setHexPIN1:
	subi	sp, sp, 4
	stw 	ra, 0(sp)

	#Set the HEX Display to say OFF
	movia 	r9, SEVEN_SEG_45
	movia 	r10, 0x00007300 
	stwio 	r10, 0(r9)
	movia 	r9, SEVEN_SEG_03
	movia 	r10, 0x00000020
	stwio 	r10, 0(r9)
	
	ldw 	ra, 0(sp)
	addi 	sp, sp, 4
	br 		poll
	
setHexPIN2:
	subi	sp, sp, 4
	stw 	ra, 0(sp)

	#Set the HEX Display to say OFF
	movia 	r9, SEVEN_SEG_45
	movia 	r10, 0x00007300 
	stwio 	r10, 0(r9)
	movia 	r9, SEVEN_SEG_03
	movia 	r10, 0x00002020 
	stwio 	r10, 0(r9)
	
	ldw 	ra, 0(sp)
	addi 	sp, sp, 4
	br 		poll

setHexPIN3:
	subi	sp, sp, 4
	stw 	ra, 0(sp)

	#Set the HEX Display to say OFF
	movia 	r9, SEVEN_SEG_45
	movia 	r10, 0x00007300
	stwio 	r10, 0(r9)
	movia 	r9, SEVEN_SEG_03
	movia 	r10, 0x00202020 
	stwio 	r10, 0(r9)
	
	ldw 	ra, 0(sp)
	addi 	sp, sp, 4
	br 		poll

pollForPassword:
	subi	sp, sp, 4
	stw 	ra, 0(sp)	

	movia 	r9, HEXKEYPAD
	mov 	r2, r0
	movi 	r12, 4

	movia 	r10, 0xF0
	stwio 	r10, 4(r9)
	stwio	r0, 0(r9)
	
	movi 	r10, 0xFF
	stwio 	r10, 12(r9)

	
poll:
	movia 	r9, HEXKEYPAD
	ldwio 	r10, 0(r9)
	andi 	r10, r10, 0x0F
	movi 	r11, 0x0F
	beq 	r10, r11, poll

	#Set rows to input, coloums to output
	movia 	r10, 0xF0
	stwio 	r10, 4(r9)

	#drive output pins to 0
	stwio	r0, 0(r9)

	#Read coloum values
	ldwio 	r10, 0(r9)
	andi 	r10, r10, 0xF

	#store to entered pin
	or 		r2, r2, r10
	slli 	r2, r2, 4

	#Set coloums to input, rows to output	
	movia 	r10, 0x0F
	stwio 	r10, 4(r9)

	stwio 	r0, 0(r9)

	ldwio 	r10, 0(r9)
	andi 	r10, r10, 0xF 
	or 		r2, r2, r10
	subi	r12, r12, 1	

	#Check if the user has entered 4 pins
	beq 	r0, r12	, exitPassword
	slli 	r2, r2, 4
	
	# Debounce loop 
	movia 	r10, 10000000
DELAY:
	subi 	r10, r10, 1
	bne 	r10, r0, DELAY
	
	#Clear the buffer
	movi 	r10, 0xF
	stwio 	r10, 12(r9)
	
	movia 	r10, 0xF0
	stwio 	r10, 4(r9)
	stwio	r0, 0(r9)
	
	#Set hexDisplay keys
	movi 	r10, 3
	beq 	r12, r10, setHexPIN1
	movi 	r10, 2
	beq 	r12, r10, setHexPIN2
	movi 	r10, 1
	beq 	r12, r10, setHexPIN3
	
	br 		poll

exitPassword:
	ldw 	ra, 0(sp)
	addi 	sp, sp, 4
	ret	

/***************************** END *****************************/
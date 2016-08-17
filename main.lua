console.clear()

boxRadius = 6
buttonNames = {
	"A",
	"B",
	"X",
	"Y",
	"Up",
	"Down",
	"Left",
	"Right",
}

layerSizes = {30, 10, 10, 10, #buttonNames}


function getTile(dx, dy)
	marioX = memory.read_s16_le(0x94)
	marioY = memory.read_s16_le(0x96)
	
	x = math.floor((marioX+dx)/16)
	y = math.floor((marioY+dy)/16)
	
	return memory.readbyte(0xC800 + math.floor(x/0x10)*0x1B0 + y*0x10 + x%0x10)
end

function getSprites()
	sprites = {}
	for slot=0,11 do
		status = memory.readbyte(0x14C8+slot)
		if status ~= 0 then
			spritex = memory.readbyte(0xE4+slot) + memory.readbyte(0x14E0+slot)*256
			spritey = memory.readbyte(0xD8+slot) + memory.readbyte(0x14D4+slot)*256
			sprites[#sprites+1] = {["x"]=spritex, ["y"]=spritey}
		end
	end		
	
	return sprites
end

function getInputs()
	marioX = memory.read_s16_le(0x94)
	marioY = memory.read_s16_le(0x96)
	
	sprites = getSprites()
	
	inputs = {}
	
	for dy=-boxRadius*16,boxRadius*16,16 do
		for dx=-boxRadius*16,boxRadius*16,16 do
			inputs[#inputs+1] = 0
			
			tile = getTile(dx, dy)
			if tile ~= 0x25 and marioY+dy < 0x1B0 then
				inputs[#inputs] = 1
			end
			
			for i = 1,#sprites do
				distx = math.abs(sprites[i]["x"] - (marioX+dx))
				disty = math.abs(sprites[i]["y"] - (marioY+dy))
				if distx < 8 and disty < 8 then
					inputs[#inputs] = -1
				end
			end
		end
	end
	
	mariovx = memory.read_s8(0x7B)
	mariovy = memory.read_s8(0x7D)
	inputs[#inputs+1] = mariovx / 70
	inputs[#inputs+1] = mariovy / 70
	
	return inputs
end


function evaluate(inputs, chromosome)
	layer = {}
	prevLayer = inputs
	c = 1
	for i=1,#layerSizes do
		layer = {}
		for n=1,layerSizes[i] do
			layer[n] = 0
		end
		for m=1,#layer do
			for n=1,#prevLayer do
				layer[m] = layer[m] + chromosome[c] * prevLayer[n]
				c = c + 1
			end
			layer[m] = math.atan(layer[m] + chromosome[c])
			c = c + 1
		end
		prevLayer = layer
	end
	
	return layer
end

function randomChromosome()
	c = {}
	
	inputs = getInputs()
	prevSize = #inputs
	for i=1,#layerSizes do
		for m=1,layerSizes[i] do
			for n=1,prevSize do
				c[#c+1] = math.random()*2-1
			end
			c[#c+1] = math.random()*2-1
		end
		prevSize = layerSizes[i]
	end
	
	return c
end

pool = {}
for i=1,20 do
	pool[i] = {["chromosome"] = randomChromosome(), ["fitness"] = 0}
end

currentChromosome = 1

function initializeRun()
	savestate.load("YI2.state");
	rightmost = 0
	frame = 0
	timeout = 120
end

function crossover(c1, c2)
	c = {["chromosome"] = {}, ["fitness"] = 0}
	pick = true
	for i=1,#c1["chromosome"] do
		if math.random(#c1["chromosome"]/4) == 1 then
			pick = not pick
		end
		if pick then
			c["chromosome"][i] = c1["chromosome"][i]
		else
			c["chromosome"][i] = c2["chromosome"][i]
		end
	end
	
	return c
end

function mutate(c)
	for i=1,#c["chromosome"] do
		if math.random(50) == 1 then
			c["chromosome"][i] = math.random()*2-1
		end
	end
end

function createNewGeneration()
	index = {}
	table.sort(pool, function (a,b)
		return (a["fitness"] > b["fitness"])
	end)
	
	
	for i=((#pool)/2),(#pool) do
		c1 = pool[math.random(#pool/2)]
		c2 = pool[math.random(#pool/2)]
		pool[i] = crossover(c1, c2)
		mutate(pool[i])
	end
	
	generation = generation + 1
end

function clearJoypad()
	controller = {}
	for b = 1,#buttonNames do
		controller["P1 " .. buttonNames[b]] = false
	end
	joypad.set(controller)
end

function showTop()
	clearJoypad()
	currentChromosome = 1
	initializeRun()
end

form = forms.newform(200, 142, "Fitness")
maxFitnessLabel = forms.label(form, "Top Fitness: ", 5, 8)
goButton = forms.button(form, "Show Top", showTop, 5, 30)
showUI = forms.checkbox(form, "Show Inputs", 5, 52)
inputsLabel = forms.label(form, "Inputs", 5, 74)

function onExit()
	forms.destroy(form)
end
event.onexit(onExit)

generation = 0
maxfitness = 0
initializeRun()

while true do
	marioX = memory.read_s16_le(0x94)
	marioY = memory.read_s16_le(0x96)

	if timeout <= 0 then
		fitness = rightmost - frame / 10
		pool[currentChromosome]["fitness"] = fitness
		
		if fitness > maxfitness then
			forms.settext(maxFitnessLabel, "Top Fitness: " .. math.floor(fitness))
			maxfitness = fitness
		end
		
		console.writeline("Generation " .. generation .. " chromosome " .. currentChromosome .. " fitness: " .. fitness)
		if currentChromosome == #pool then
			createNewGeneration()
			currentChromosome = 1
		else
			currentChromosome = currentChromosome + 1
		end
		initializeRun()
	end

	inputs = getInputs()
	if timeout > 2 and frame % 5 == 0 then
		outputs = evaluate(inputs, pool[currentChromosome]["chromosome"])
		
		controller = {}
		inputsString = ""
		for n = 1,#buttonNames do
			if outputs[n] > 0 then
				controller["P1 " .. buttonNames[n]] = true
				inputsString = inputsString .. buttonNames[n]
			else 
				controller["P1 " .. buttonNames[n]] = false
			end
		end
		
		forms.settext(inputsLabel, inputsString)
	end
	joypad.set(controller)
	
	if timeout <= 2 then
		clearJoypad()
	end
	
	if marioX > rightmost then
		timeout = 120
		rightmost = marioX
	end
	
	timeout = timeout - 1
	frame = frame + 1
	
	
	if forms.ischecked(showUI) then
		layer1x = memory.read_s16_le(0x1A);
		layer1y = memory.read_s16_le(0x1C);
 		
		for dy = 0,boxRadius*2 do
			for dx = 0,boxRadius*2 do
				input = inputs[dy*(boxRadius*2+1)+dx+1]
				gui.drawText(marioX+(dx-boxRadius)*16-layer1x,marioY+(dy-boxRadius)*16-layer1y,string.format("%i", input),0x80FFFFFF, 11)
			end
		end
	end
	
	emu.frameadvance();
end
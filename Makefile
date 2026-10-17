NVIM ?= nvim

.PHONY: test deps

test: deps
	$(NVIM) --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

deps: deps/mini.nvim

deps/mini.nvim:
	git clone --depth 1 --branch stable https://github.com/nvim-mini/mini.nvim $@

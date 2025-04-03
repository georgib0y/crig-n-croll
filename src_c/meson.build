test_magic_src = src_files + files('test_magic.c')
test_magic_exe = executable('magic', test_magic_src, include_directories: inc_dir, native: true)

test_perft_src = src_files + files('perft.c')
test_perft_exe = executable(
  'perft',
  test_perft_src,
  include_directories: inc_dir,
  native: true,
  c_args: [
    '-flto',
    '-Ofast',
    '-march=native',
    '-mtune=native',
    # '-DHASHING',
    # '-DEVAL'
  ]
)

test_fen_src = src_files + files('test_fen.c')
test_fen_exe = executable('fen', test_fen_src, include_directories: inc_dir, native: true, c_args: ['-DDEBUG'])

test_perftree_src = src_files + files('perftree.c')
test_perftree_exe = executable(
  'perftree',
  test_perftree_src,
  include_directories: inc_dir,
  native: true,
  c_args: [
    '-flto',
    '-Ofast',
    '-march=native',
    '-mtune=native',
    # '-DDEBUG'
  ]
)

test_hashing_src = src_files + files('test_hashing.c')
test_hashing_exe = executable(
  'hashing',
  test_hashing_src,
  include_directories: inc_dir,
  native: true,
  c_args: [
    '-flto',
    '-Ofast',
    '-march=native',
    '-mtune=native',
    # '-DDEBUG',
    '-DHASHING'
  ]
)

test_eval_src = src_files + files('test_eval.c')
test_eval_exe = executable(
  'eval',
  test_eval_src,
  include_directories: inc_dir,
  native: true,
  c_args: [
    '-flto',
    '-Ofast',
    '-march=native',
    '-mtune=native',
    # '-DDEBUG',
    '-DEVAL'
  ]
)

test_search_src = src_files + files('test_search.c')
test_search_exe = executable(
  'search',
  test_search_src,
  include_directories: inc_dir,
  native: true,
  c_args: [
    '-g',
    # '-flto',
    # '-Ofast',
    # '-march=native',
    # '-mtune=native',
    '-DDEBUG',
    '-DHASHING',
    '-DEVAL',
  ]
)

test('magic', test_magic_exe)
test('perft', test_perft_exe, timeout: 180)
test('fen', test_fen_exe)
test('perftree', test_perftree_exe, timeout: 0)
test('hashing', test_hashing_exe, timeout: 60)
test('eval', test_eval_exe, timeout: 60)
test('search', test_search_exe, timeout: 60)

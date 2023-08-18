{ lib, buildPythonPackage, fetchFromGitHub, cython, jq, pytestCheckHook }:

buildPythonPackage rec {
  pname = "jq";
  version = "1.4.1";

  src = fetchFromGitHub {
    owner = "mwilliamson";
    repo = "jq.py";
    rev = version;
    hash = "sha256-prH3yUFh3swXGsxnoax09aYAXaiu8o2M21ZbOp9HDJY=";
  };

  patches = [
    # Removes vendoring
    ./jq-py-setup.patch
  ];

  nativeBuildInputs = [ cython ];

  buildInputs = [ jq ];

  preBuild = ''
    cython jq.pyx
  '';

  nativeCheckInputs = [
    pytestCheckHook
  ];

  pythonImportsCheck = [ "jq" ];

  meta = {
    description = "Python bindings for jq, the flexible JSON processor";
    homepage = "https://github.com/mwilliamson/jq.py";
    license = lib.licenses.bsd2;
    maintainers = with lib.maintainers; [ benley ];
  };
}
